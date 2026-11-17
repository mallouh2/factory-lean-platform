-- F36: eliminate repeated full timezone-catalog scans within one shift resolution.
-- Public/legacy boundary and descriptor entry points retain their original validation.
-- Only this resolver can select the private fast path after a positive catalog check.
-- The original offset enumeration, DST fold/gap checks and frozen facts are unchanged.
CREATE OR REPLACE FUNCTION private.shift_boundary_utc_known_zone(wall timestamp without time zone, zone text)
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$declare candidates timestamptz[];begin
 if wall is null or not isfinite(wall)
 then raise exception 'shift_window_invalid' using errcode='22023';end if;
 select array_agg(distinct candidate) into candidates from (
  select (wall at time zone 'UTC')-((sample at time zone zone)-(sample at time zone 'UTC')) candidate
  from pg_catalog.generate_series((wall at time zone 'UTC')-interval '36 hours',
   (wall at time zone 'UTC')+interval '36 hours',interval '6 hours') sample
 ) offsets where candidate at time zone zone=wall;
 if coalesce(cardinality(candidates),0)=0 then raise exception 'shift_boundary_nonexistent' using errcode='22023';end if;
 if cardinality(candidates)<>1 then raise exception 'shift_boundary_ambiguous' using errcode='22023';end if;
 return candidates[1];
end$function$;
revoke all on function private.shift_boundary_utc_known_zone(timestamp,text)from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.shift_occurrence_descriptor_known_zone(r private.production_shift_schedule_revisions, s jsonb, d date)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare a timestamptz;b timestamptz;key text;frozen jsonb;begin
 -- A persisted fact survives later timezone-database changes. Never reinterpret it.
 select to_jsonb(o)-'materialized_at' into frozen from private.production_shift_occurrences o
 where o.factory_id=r.factory_id and o.schedule_revision_id=r.id and o.shift_id=(s->>'id')::uuid and o.business_date=d;
 if frozen is not null then return frozen;end if;
 if (s->>'archived')::boolean or s->>'start_time' is null or s->>'end_time' is null then return null;end if;
 a:=private.shift_boundary_utc_known_zone(d+(s->>'start_time')::time,r.timezone);
 b:=private.shift_boundary_utc_known_zone((d+case when (s->>'end_time')::time<(s->>'start_time')::time then 1 else 0 end)+(s->>'end_time')::time,r.timezone);
 if b<=a then raise exception 'shift_window_invalid' using errcode='22023';end if;
 key:=encode(sha256(convert_to(jsonb_build_array(1,r.factory_id::text,r.id::text,s->>'id',d::text,
  to_char(a,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),to_char(b,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex');
 return jsonb_build_object('identity_version',1,'factory_id',r.factory_id,'occurrence_key',key,
  'schedule_revision_id',r.id,'shift_id',s->>'id','business_date',d,'timezone',r.timezone,
  'name',s->>'name','name_ar',s->>'name_ar','starts_at',a,'ends_at',b);
end$function$;
revoke all on function private.shift_occurrence_descriptor_known_zone(private.production_shift_schedule_revisions,jsonb,date)from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION private.resolve_production_occurrence(f uuid, evaluated timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
 SET "TimeZone" TO 'UTC'
AS $function$
declare r private.production_shift_schedule_revisions;pending private.production_shift_schedule_revisions;
 s jsonb;candidate jsonb;local_now timestamp;wall_start timestamp;wall_end timestamp;d date;offset_day integer;
 first_start timestamptz;next_start timestamptz;reason text:='SCHEDULE_GAP';found_occ jsonb;zone_known boolean;begin
 if evaluated is null or not isfinite(evaluated) then raise exception 'shift_work_invalid' using errcode='22023';end if;
 select * into r from private.production_shift_schedule_revisions where factory_id=f and effective_from<=evaluated
 order by effective_from desc,revision_no desc limit 1;
 select * into pending from private.production_shift_schedule_revisions where factory_id=f and effective_from>evaluated
 order by effective_from desc,revision_no desc limit 1;
 select to_jsonb(o)-'materialized_at' into found_occ from private.production_shift_occurrences o
 where o.factory_id=f and o.starts_at<=evaluated and o.ends_at>evaluated;
 if found_occ is not null then return jsonb_build_object('available',true,'reason',null,'occurrence',found_occ,
  'timezone',found_occ->>'timezone','late_recording_available',false,'pending',
  case when pending.id is not null then jsonb_build_object('revision_id',pending.id,'effective_from',pending.effective_from,'timezone',pending.timezone) end);end if;
 if r.id is null then return jsonb_build_object('available',false,'reason','OCCURRENCE_NOT_READY',
  'not_before',pending.effective_from,'late_recording_available',false);end if;
 local_now:=evaluated at time zone r.timezone;
 if not exists(select 1 from jsonb_array_elements(r.definitions) x where not (x->>'archived')::boolean and x->>'start_time' is not null)
 then reason:='SHIFT_CONFIGURATION_UNAVAILABLE';end if;
 for offset_day in -1..0 loop
  d:=local_now::date+offset_day;
  for s in select value from jsonb_array_elements(r.definitions) where not (value->>'archived')::boolean and value->>'start_time' is not null loop
   wall_start:=d+(s->>'start_time')::time;
   wall_end:=(d+case when (s->>'end_time')::time<(s->>'start_time')::time then 1 else 0 end)+(s->>'end_time')::time;
   if local_now<wall_start or local_now>=wall_end then continue;end if;
   begin -- Validate a recognized zone once within this resolution, never across calls.
   if zone_known is null then select exists(select 1 from pg_catalog.pg_timezone_names where name=r.timezone)into zone_known;end if;
   if zone_known then candidate:=private.shift_occurrence_descriptor_known_zone(r,s,d);
   else candidate:=private.shift_occurrence_descriptor(r,s,d);end if;
   exception when sqlstate '22023' then
    return jsonb_build_object('available',false,'reason',upper(sqlerrm),'timezone',r.timezone,'late_recording_available',false);
   end;
   if (candidate->>'starts_at')::timestamptz<r.effective_from then reason:='OCCURRENCE_NOT_READY';continue;end if;
   if evaluated>=(candidate->>'starts_at')::timestamptz and evaluated<(candidate->>'ends_at')::timestamptz then
    if found_occ is not null then return jsonb_build_object('available',false,'reason','SHIFT_OVERLAP','late_recording_available',false);end if;
    found_occ:=candidate;
   end if;
  end loop;
 end loop;
 -- A newly captured revision cannot certify an already elapsed part of a shift.
 for offset_day in 0..2 loop
  for s in select value from jsonb_array_elements(r.definitions) where not (value->>'archived')::boolean and value->>'start_time' is not null loop
   begin -- Validate a recognized zone once within this resolution, never across calls.
   if zone_known is null then select exists(select 1 from pg_catalog.pg_timezone_names where name=r.timezone)into zone_known;end if;
   if zone_known then candidate:=private.shift_occurrence_descriptor_known_zone(r,s,(r.effective_from at time zone r.timezone)::date+offset_day);
   else candidate:=private.shift_occurrence_descriptor(r,s,(r.effective_from at time zone r.timezone)::date+offset_day);end if;
   exception when sqlstate '22023' then continue;end;
   if (candidate->>'starts_at')::timestamptz>=r.effective_from then
    first_start:=least(first_start,(candidate->>'starts_at')::timestamptz);
   end if;
  end loop;
 end loop;
 if found_occ is null and first_start>evaluated then reason:='OCCURRENCE_NOT_READY';end if;
 return jsonb_build_object('available',found_occ is not null,'reason',case when found_occ is null then reason end,
  'occurrence',found_occ,'timezone',r.timezone,'first_verified_start',first_start,'late_recording_available',false,
  'pending',case when pending.id is not null then jsonb_build_object('revision_id',pending.id,'effective_from',pending.effective_from,'timezone',pending.timezone) end);
end$function$;
