-- Run only through the identity-guarded local QA runner documented in README.md.
-- pg_temp.f36_original_resolver is compiled from the untouched historical migration.
create function pg_temp.f36_boundary(wall timestamp,zone text,fast boolean)returns jsonb
language plpgsql as $$declare value timestamptz;begin
 if fast then value:=private.shift_boundary_utc_known_zone(wall,zone);
 else value:=private.shift_boundary_utc(wall,zone);end if;
 return jsonb_build_object('value',value);
exception when others then return jsonb_build_object('state',sqlstate,'error',sqlerrm);end$$;
do $test$
declare r record;wall timestamp;zone text;a jsonb;b jsonb;f uuid;stamp timestamptz;
 schedule private.production_shift_schedule_revisions;definition jsonb;occ jsonb;
begin
 for r in select *from(values
 ('UTC','2026-11-15 12:00'),('Asia/Qatar','2026-11-15 12:00'),
 ('Asia/Kathmandu','2026-11-15 12:00'),('Pacific/Chatham','2026-11-15 12:00'),
 ('America/New_York','2026-03-08 01:59'),('America/New_York','2026-03-08 02:30'),
 ('America/New_York','2026-03-08 03:00'),('America/New_York','2026-11-01 01:30'),
 ('America/New_York','2026-11-01 02:00'),('Europe/London','2026-03-29 01:30'),
 ('Europe/London','2026-10-25 01:30'),('Australia/Lord_Howe','2026-04-05 01:45'),
 ('Australia/Lord_Howe','2026-10-04 02:15'),('Pacific/Apia','2011-12-30 12:00'),
 ('Asia/Kathmandu','1986-01-01 00:05'),('Europe/Amsterdam','1900-01-01 12:00:17'),
 ('UTC',null),('UTC','infinity'),('UTC','-infinity'),
 ('Africa/Casablanca','2026-03-22 12:00'))v(zone,wall)loop
  a:=pg_temp.f36_boundary(r.wall::timestamp,r.zone,false);b:=pg_temp.f36_boundary(r.wall::timestamp,r.zone,true);
  if a is distinct from b then raise exception 'Boundary mismatch: % %: % / %',r.zone,r.wall,a,b;end if;
 end loop;
 -- The invalid-name and abbreviation entry point is deliberately unchanged.
 foreach zone in array array['Not/A_Zone','utc','PST','+03']loop
  a:=pg_temp.f36_boundary('2026-11-15 12:00',zone,false);
  if a->>'error'<>'shift_window_invalid'then raise exception 'Original zone rejection changed: % %',zone,a;end if;
 end loop;
 for f in select id from public.factories where id=any(current_setting('f36.factories')::uuid[])loop
  foreach stamp in array array['2026-11-11 10:51Z'::timestamptz,'2026-11-11 10:53Z',clock_timestamp(),clock_timestamp()+interval '1 hour',clock_timestamp()+interval '1 day']loop
   a:=pg_temp.f36_original_resolver(f,stamp);b:=private.resolve_production_occurrence(f,stamp);
   if a is distinct from b then raise exception 'Resolver mismatch: % %',f,stamp;end if;
  end loop;
 end loop;
 f:=current_setting('f36.factory')::uuid;
 occ:=private.resolve_production_occurrence(f,clock_timestamp())->'occurrence';
 if occ is null then raise exception 'Frozen-fact test requires an actual current QA shift';end if;
 perform private.materialize_production_occurrence(f,occ);
 select *into schedule from private.production_shift_schedule_revisions where factory_id=f and id=(occ->>'schedule_revision_id')::uuid;
 select value into definition from jsonb_array_elements(schedule.definitions)where value->>'id'=occ->>'shift_id';
 -- A persisted occurrence must survive an unavailable historical zone name.
 schedule.timezone:='Not/A_Zone';
 if private.shift_occurrence_descriptor(schedule,definition,(occ->>'business_date')::date)is distinct from occ
 or private.shift_occurrence_descriptor_known_zone(schedule,definition,(occ->>'business_date')::date)is distinct from occ then raise exception 'Frozen fact reinterpreted';end if;
 if pg_temp.f36_original_resolver(f,clock_timestamp())is distinct from private.resolve_production_occurrence(f,clock_timestamp())then raise exception 'Materialized resolver drift';end if;
 if exists(select 1 from pg_proc p cross join unnest(array['anon','authenticated','service_role'])role
  where p.oid in('private.shift_boundary_utc_known_zone(timestamp,text)'::regprocedure,
   'private.shift_occurrence_descriptor_known_zone(private.production_shift_schedule_revisions,jsonb,date)'::regprocedure)
  and has_function_privilege(role,p.oid,'EXECUTE'))then raise exception 'Private helper exposed';end if;
end$test$;
