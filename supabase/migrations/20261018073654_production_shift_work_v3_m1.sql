-- Phase 1 only: prospective shift evidence and protected reads. No output writer changes.
begin;

create table private.production_shift_schedule_revisions (
 factory_id uuid not null references public.factories, id uuid not null default gen_random_uuid(),
 revision_no bigint not null check(revision_no>0), predecessor_id uuid,
 recorded_at timestamptz not null, recorded_by uuid references auth.users,
 source text not null check(source in ('BASELINE_CAPTURE','SHIFT_CONFIGURATION','TIMEZONE_CONFIGURATION')),
 effective_from timestamptz not null, timezone text not null, definitions jsonb not null,
 definition_hash text not null check(definition_hash ~ '^[0-9a-f]{64}$'), transition_reason text,
 primary key(factory_id,id), unique(factory_id,revision_no),
 foreign key(factory_id,predecessor_id) references private.production_shift_schedule_revisions(factory_id,id),
 check(isfinite(recorded_at) and isfinite(effective_from) and effective_from>=recorded_at),
 check(jsonb_typeof(definitions)='array')
);
create index on private.production_shift_schedule_revisions(factory_id,effective_from desc,revision_no desc);
create table private.production_shift_occurrences (
 factory_id uuid not null references public.factories, occurrence_key text not null check(occurrence_key ~ '^[0-9a-f]{64}$'),
 schedule_revision_id uuid not null, shift_id uuid not null, business_date date not null,
 timezone text not null, name text not null, name_ar text not null,
 starts_at timestamptz not null, ends_at timestamptz not null,
 identity_version smallint not null default 1 check(identity_version=1),
 materialized_at timestamptz not null default clock_timestamp(), primary key(factory_id,occurrence_key),
 unique(factory_id,schedule_revision_id,shift_id,business_date),
 foreign key(factory_id,schedule_revision_id) references private.production_shift_schedule_revisions(factory_id,id),
 foreign key(factory_id,shift_id) references public.production_shifts(factory_id,id),
 check(isfinite(starts_at) and isfinite(ends_at) and ends_at>starts_at),
 exclude using gist(factory_id extensions.gist_uuid_ops with =,(tstzrange(starts_at,ends_at,'[)')) with &&)
);
create index on private.production_shift_occurrences(factory_id,starts_at,occurrence_key);
alter table private.production_shift_schedule_revisions enable row level security;
alter table private.production_shift_occurrences enable row level security;
revoke all on private.production_shift_schedule_revisions,private.production_shift_occurrences from public,anon,authenticated;
create function private.production_shift_immutable() returns trigger language plpgsql set search_path='' as $$begin
 raise exception 'shift_history_immutable' using errcode='22023';end$$;
create trigger shift_revision_immutable before update or delete on private.production_shift_schedule_revisions
 for each row execute function private.production_shift_immutable();
create trigger shift_occurrence_immutable before update or delete on private.production_shift_occurrences
 for each row execute function private.production_shift_immutable();

-- Round-trip all distinct nearby UTC offsets, rather than accepting PostgreSQL's
-- default choice for a repeated/nonexistent local boundary. No client clock input.
create function private.shift_boundary_utc(wall timestamp,zone text) returns timestamptz
language plpgsql stable set search_path='' as $$declare candidates timestamptz[];begin
 if wall is null or not isfinite(wall) or not exists(select 1 from pg_catalog.pg_timezone_names where name=zone)
 then raise exception 'shift_window_invalid' using errcode='22023';end if;
 select array_agg(distinct candidate) into candidates from (
  select (wall at time zone 'UTC')-((sample at time zone zone)-(sample at time zone 'UTC')) candidate
  from pg_catalog.generate_series((wall at time zone 'UTC')-interval '36 hours',
   (wall at time zone 'UTC')+interval '36 hours',interval '6 hours') sample
 ) offsets where candidate at time zone zone=wall;
 if coalesce(cardinality(candidates),0)=0 then raise exception 'shift_boundary_nonexistent' using errcode='22023';end if;
 if cardinality(candidates)<>1 then raise exception 'shift_boundary_ambiguous' using errcode='22023';end if;
 return candidates[1];
end$$;

create function private.shift_occurrence_descriptor(r private.production_shift_schedule_revisions,s jsonb,d date)
returns jsonb language plpgsql stable set search_path='' set timezone='UTC' as $$
declare a timestamptz;b timestamptz;key text;frozen jsonb;begin
 -- A persisted fact survives later timezone-database changes. Never reinterpret it.
 select to_jsonb(o)-'materialized_at' into frozen from private.production_shift_occurrences o
 where o.factory_id=r.factory_id and o.schedule_revision_id=r.id and o.shift_id=(s->>'id')::uuid and o.business_date=d;
 if frozen is not null then return frozen;end if;
 if (s->>'archived')::boolean or s->>'start_time' is null or s->>'end_time' is null then return null;end if;
 a:=private.shift_boundary_utc(d+(s->>'start_time')::time,r.timezone);
 b:=private.shift_boundary_utc((d+case when (s->>'end_time')::time<(s->>'start_time')::time then 1 else 0 end)+(s->>'end_time')::time,r.timezone);
 if b<=a then raise exception 'shift_window_invalid' using errcode='22023';end if;
 key:=encode(sha256(convert_to(jsonb_build_array(1,r.factory_id::text,r.id::text,s->>'id',d::text,
  to_char(a,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'),to_char(b,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex');
 return jsonb_build_object('identity_version',1,'factory_id',r.factory_id,'occurrence_key',key,
  'schedule_revision_id',r.id,'shift_id',s->>'id','business_date',d,'timezone',r.timezone,
  'name',s->>'name','name_ar',s->>'name_ar','starts_at',a,'ends_at',b);
end$$;

create function private.resolve_production_occurrence(f uuid,evaluated timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare r private.production_shift_schedule_revisions;pending private.production_shift_schedule_revisions;
 s jsonb;candidate jsonb;local_now timestamp;wall_start timestamp;wall_end timestamp;d date;offset_day integer;
 first_start timestamptz;next_start timestamptz;reason text:='SCHEDULE_GAP';found_occ jsonb;begin
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
   begin candidate:=private.shift_occurrence_descriptor(r,s,d);
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
   begin candidate:=private.shift_occurrence_descriptor(r,s,(r.effective_from at time zone r.timezone)::date+offset_day);
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
end$$;

create function private.append_production_shift_revision(f uuid,origin text) returns uuid
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare previous private.production_shift_schedule_revisions;stamp timestamptz;effective timestamptz;zone text;defs jsonb;
 current_context jsonb;s jsonb;candidate jsonb;day date;result uuid;begin
 perform private.maintenance_planning_lock(f);stamp:=clock_timestamp();effective:=stamp;
 select timezone into zone from public.factories where id=f;
 if zone is null then raise exception 'shift_work_invalid' using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',id,'name',name,'name_ar',name_ar,'start_time',start_time,
  'end_time',end_time,'archived',archived) order by id),'[]') into defs from public.production_shifts where factory_id=f;
 select * into previous from private.production_shift_schedule_revisions where factory_id=f order by revision_no desc limit 1;
 if previous.id is not null and previous.timezone=zone and previous.definitions=defs then return previous.id;end if;
 if previous.id is not null then
  current_context:=private.resolve_production_occurrence(f,stamp);
  if current_context->>'reason' in ('SHIFT_BOUNDARY_AMBIGUOUS','SHIFT_BOUNDARY_NONEXISTENT','SHIFT_OVERLAP')
  then raise exception 'shift_transition_ambiguous' using errcode='22023';end if;
  effective:=greatest(stamp,previous.effective_from,(current_context#>>'{occurrence,ends_at}')::timestamptz);
 else
  -- Capture an honest future fence using observed legacy configuration, never past evidence.
  for s in select value from jsonb_array_elements(defs) where not (value->>'archived')::boolean and value->>'start_time' is not null loop
   day:=(stamp at time zone zone)::date;
   if (s->>'start_time')::time>(s->>'end_time')::time and (stamp at time zone zone)::time<(s->>'end_time')::time then day:=day-1;end if;
   begin
    candidate:=private.shift_occurrence_descriptor((f,gen_random_uuid(),1,null,stamp,null,'BASELINE_CAPTURE',stamp,zone,defs,repeat('0',64),null)::private.production_shift_schedule_revisions,s,day);
    if stamp>=(candidate->>'starts_at')::timestamptz and stamp<(candidate->>'ends_at')::timestamptz then effective:=greatest(effective,(candidate->>'ends_at')::timestamptz);end if;
   exception when sqlstate '22023' then
    -- No safe current boundary: tomorrow is a conservative prospective fence.
    effective:=greatest(effective,private.shift_boundary_utc(((stamp at time zone zone)::date+1)::timestamp,zone));
   end;
  end loop;
 end if;
 if exists(select 1 from private.production_shift_occurrences where factory_id=f and ends_at>effective) then
  raise exception 'shift_transition_frozen' using errcode='40001';
 end if;
 insert into private.production_shift_schedule_revisions(factory_id,revision_no,predecessor_id,recorded_at,recorded_by,source,effective_from,timezone,definitions,definition_hash,transition_reason)
 values(f,coalesce(previous.revision_no,0)+1,previous.id,stamp,auth.uid(),origin,effective,zone,defs,
  encode(sha256(convert_to(jsonb_build_array(1,zone,defs)::text,'UTF8')),'hex'),case when effective>stamp then 'PROSPECTIVE_FENCE' end) returning id into result;
 return result;
end$$;

create function private.materialize_production_occurrence(f uuid,descriptor jsonb) returns text
language plpgsql volatile security definer set search_path='' set timezone='UTC' as $$
declare r private.production_shift_schedule_revisions;existing private.production_shift_occurrences;expected jsonb;s jsonb;k text;begin
 perform private.maintenance_planning_lock(f);
 select * into r from private.production_shift_schedule_revisions where factory_id=f and id=(descriptor->>'schedule_revision_id')::uuid;
 select value into s from jsonb_array_elements(r.definitions) where value->>'id'=descriptor->>'shift_id';
 if r.id is null or s is null then raise exception 'shift_work_invalid' using errcode='22023';end if;
 expected:=private.shift_occurrence_descriptor(r,s,(descriptor->>'business_date')::date);
 if expected is distinct from descriptor or (expected->>'starts_at')::timestamptz<r.effective_from
 or r.id is distinct from (select id from private.production_shift_schedule_revisions where factory_id=f and effective_from<=(expected->>'starts_at')::timestamptz order by effective_from desc,revision_no desc limit 1)
 or exists(select 1 from private.production_shift_schedule_revisions where factory_id=f and effective_from>r.effective_from and effective_from<(expected->>'ends_at')::timestamptz)
 then raise exception 'shift_occurrence_conflict' using errcode='40001';end if;
 k:=expected->>'occurrence_key';
 insert into private.production_shift_occurrences(factory_id,occurrence_key,schedule_revision_id,shift_id,business_date,timezone,name,name_ar,starts_at,ends_at)
 values(f,k,r.id,(expected->>'shift_id')::uuid,(expected->>'business_date')::date,r.timezone,expected->>'name',expected->>'name_ar',(expected->>'starts_at')::timestamptz,(expected->>'ends_at')::timestamptz)
 on conflict(factory_id,occurrence_key) do nothing;
 select * into existing from private.production_shift_occurrences where factory_id=f and occurrence_key=k;
 if to_jsonb(existing)-'materialized_at' is distinct from expected then raise exception 'shift_occurrence_conflict' using errcode='40001';end if;
 return k;
end$$;

-- Wrap configuration only; inherited validations, audit, Maintenance locks and signatures survive.
alter function public.configure_production_shift(uuid,text,text,time,time,uuid,boolean) rename to configure_shift_before_occurrences;
alter function public.configure_shift_before_occurrences(uuid,text,text,time,time,uuid,boolean) set schema private;
create function public.configure_production_shift(factory uuid,name text,name_ar text,start_time time,end_time time,id uuid default null,archived boolean default false)
returns uuid language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform private.require_permission(factory,'settings','edit');perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'settings','edit');
 result:=private.configure_shift_before_occurrences(factory,name,name_ar,start_time,end_time,id,archived);
 perform private.append_production_shift_revision(factory,'SHIFT_CONFIGURATION');return result;
end$$;
alter function private.update_settings(uuid,text,text,text) rename to settings_before_shift_occurrences;
create function private.update_settings(f uuid,n text,tz text,logo text) returns void language plpgsql security definer set search_path='' as $$declare before_zone text;begin
 perform private.require_permission(f,'settings','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'settings','edit');select timezone into before_zone from public.factories where id=f;
 perform private.settings_before_shift_occurrences(f,n,tz,logo);
 if before_zone is distinct from tz then perform private.append_production_shift_revision(f,'TIMEZONE_CONFIGURATION');end if;
end$$;
create function private.seed_production_shift_revision() returns trigger language plpgsql security definer set search_path='' as $$begin
 perform private.append_production_shift_revision(new.id,'BASELINE_CAPTURE');return new;end$$;
create trigger zzzz_seed_production_shift_revision after insert on public.factories for each row execute function private.seed_production_shift_revision();
do $$declare f uuid;begin for f in select id from public.factories order by id loop perform private.append_production_shift_revision(f,'BASELINE_CAPTURE');end loop;end$$;

-- Names/unit/header labels and private schedule changes also affect a complete page.
create trigger shift_work_source_changed after insert on private.production_shift_schedule_revisions for each row execute function private.lean_source_changed();
create trigger shift_work_product_changed after insert or update or delete on public.products for each row execute function private.lean_source_changed();
create trigger shift_work_request_changed after insert or update or delete on public.production_requests for each row execute function private.lean_source_changed();

create function private.production_recording_eligibility(job public.production_orders,occurrence jsonb,evaluated timestamptz)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare reason text;k text;planned_line uuid;live boolean;begin
 if evaluated is null or not isfinite(evaluated) or evaluated<(occurrence->>'starts_at')::timestamptz or evaluated>=(occurrence->>'ends_at')::timestamptz then reason:='OUTSIDE_CURRENT_SHIFT';
 elsif job.factory_id is distinct from (occurrence->>'factory_id')::uuid or job.line_id is null or not exists(select 1 from public.production_lines where factory_id=job.factory_id and id=job.line_id) then reason:='EXECUTED_LINE_UNVERIFIED';
 elsif job.actual_start is null then reason:='ACTUAL_START_MISSING';
 elsif job.actual_start>evaluated or (job.actual_finish is not null and job.actual_finish>evaluated) then reason:='EXECUTION_IN_FUTURE';
 elsif (job.status='active' and job.actual_finish is not null) or (job.status='completed' and (job.actual_finish is null or job.actual_finish<=job.actual_start)) or job.status not in ('active','completed') then reason:='EXECUTION_STATE_INVALID';
 elsif job.actual_start>=(occurrence->>'ends_at')::timestamptz or (job.actual_finish is not null and job.actual_finish<=(occurrence->>'starts_at')::timestamptz) then reason:='OUTSIDE_CURRENT_SHIFT';
 else
  select after_line_id into planned_line from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at<=job.actual_start order by revision_no desc limit 1;
  if not job.planning_ever_scheduled or planned_line is distinct from job.line_id or exists(
   select 1 from public.production_plan_revisions where factory_id=job.factory_id and item_id=job.id and changed_at>job.actual_start and after_line_id is distinct from job.line_id)
  then reason:='EXECUTED_LINE_UNVERIFIED';end if;
 end if;
 k:=case when job.actual_start is not null and job.line_id is not null then encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.line_id,to_char(job.actual_start,'YYYY-MM-DD"T"HH24:MI:SS.US"Z"'))::text,'UTF8')),'hex') end;
 live:=false;
 if reason is null and job.status='active' then
  live:=exists(select 1 from private.production_recording_units(job.factory_id) u where u.unit_kind='line' and u.unit_id=job.line_id and u.item_id=job.id);
 end if;
 return jsonb_build_object('included',reason is null,'preview_selectable',reason is null,'execution_key',k,
  'policy_late_eligible',reason is null and job.status='completed','active_recording_eligible',coalesce(live,false),
  'late_recording_available',false,'blocked_reason',coalesce(reason,case when job.status='completed' then 'PHASE1_READ_ONLY' when not live then 'ACTIVE_UNIT_UNAVAILABLE' end),
  'resource_evidence',jsonb_build_object('line','PROTECTED_PLAN_EXECUTION','machines','UNKNOWN'),
  'context_hash',encode(sha256(convert_to(jsonb_build_array(1,job.factory_id,job.id,job.product_id,job.line_id,job.actual_start,job.actual_finish,job.status,job.unit,job.target_quantity,job.accepted_good_quantity,job.fulfillment_good_quantity,occurrence->>'occurrence_key',live)::text,'UTF8')),'hex'));
end$$;

create function public.production_shift_work(factory uuid,cursor jsonb default null,page_size integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' set timezone='UTC' as $$
declare stamp timestamptz:=clock_timestamp();evaluated timestamptz;ctx jsonb;occ jsonb;rev bigint;schedule_rev bigint;
 context_key text;rows jsonb;total bigint;next_page jsonb;can_edit boolean;begin
 perform private.require_permission(factory,'orders','view');
 if page_size is null or page_size not between 1 and 100 or (cursor is not null and (jsonb_typeof(cursor)<>'object' or octet_length(cursor::text)>3000 or
  not (cursor ?& array['version','factory','occurrence','as_of','revision','schedule_revision','page_size','context','last_state','last_start','last_id']) or
  exists(select 1 from jsonb_object_keys(cursor) k where k not in ('version','factory','occurrence','as_of','revision','schedule_revision','page_size','context','last_state','last_start','last_id'))))
 then raise exception 'shift_work_invalid' using errcode='22023';end if;
 ctx:=private.resolve_production_occurrence(factory,stamp);occ:=ctx->'occurrence';
 select coalesce(revision,0) into rev from private.lean_source_state where factory_id=factory;rev:=coalesce(rev,0);
 select coalesce(max(revision_no),0) into schedule_rev from private.production_shift_schedule_revisions where factory_id=factory;
 if cursor is not null then
  if cursor->>'factory' is distinct from factory::text or cursor->>'version' is distinct from '1' or cursor->>'page_size' is distinct from page_size::text
   or cursor->>'occurrence' is distinct from occ->>'occurrence_key' or cursor->>'revision' is distinct from rev::text or cursor->>'schedule_revision' is distinct from schedule_rev::text
   or coalesce(cursor->>'last_state','') not in ('0','1') or cursor->>'last_start' is null or cursor->>'last_id' is null
  then raise exception 'shift_work_stale' using errcode='40001';end if;
  evaluated:=(cursor->>'as_of')::timestamptz;
  if evaluated is null or not isfinite(evaluated) or evaluated>stamp or evaluated<(occ->>'starts_at')::timestamptz
  then raise exception 'shift_work_invalid' using errcode='22023';end if;
 else evaluated:=stamp;end if;
 context_key:=encode(sha256(convert_to(jsonb_build_array(1,factory,occ->>'occurrence_key',evaluated,rev,schedule_rev,page_size)::text,'UTF8')),'hex');
 if cursor is not null and cursor->>'context' is distinct from context_key then raise exception 'shift_work_stale' using errcode='40001';end if;
 can_edit:=private.has_permission(factory,'orders','edit');
 if (ctx->>'available')::boolean is not true then return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,
  'rows','[]'::jsonb,'total',0,'page_size',page_size,'complete',true,'next_cursor',null,'can_edit',can_edit,'late_recording_available',false);end if;
 with candidates as materialized (
  select o,private.production_recording_eligibility(o,occ,evaluated) eligibility,
   case when o.status='active' then 0 else 1 end state_rank
  from public.production_orders o where o.factory_id=factory and o.line_id is not null and o.status in ('active','completed')
   and o.actual_start<=evaluated and o.actual_start<(occ->>'ends_at')::timestamptz
   and (o.actual_finish is null or o.actual_finish>(occ->>'starts_at')::timestamptz)
 ),included as materialized(select * from candidates where (eligibility->>'included')::boolean),
 remaining as (select * from included where cursor is null or
  (state_rank,-extract(epoch from (o).actual_start),(o).id)>((cursor->>'last_state')::integer,-extract(epoch from (cursor->>'last_start')::timestamptz),(cursor->>'last_id')::uuid)),
 page as materialized(select * from remaining order by state_rank,(o).actual_start desc,(o).id limit page_size+1),
 selected as (select * from page order by state_rank,(o).actual_start desc,(o).id limit page_size)
 select (select count(*) from included),coalesce(jsonb_agg(
  jsonb_build_object('item_id',(s.o).id,'item_code',(s.o).code,'request_id',r.id,'request_code',r.code,
   'product_id',p.id,'product_name',p.name,'product_name_ar',p.name_ar,'unit',(s.o).unit,
   'line_id',l.id,'line_name',l.name,'line_name_ar',l.name_ar,'actual_start',(s.o).actual_start,'actual_finish',(s.o).actual_finish,'status',(s.o).status,
   'accepted_good',(s.o).accepted_good_quantity,'fulfillment_good',(s.o).fulfillment_good_quantity,'remaining_quantity',(s.o).accepted_remaining_quantity,
   'can_record',can_edit and (s.eligibility->>'active_recording_eligible')::boolean,'recent_entry_scope',jsonb_build_object('item_id',(s.o).id,'line_id',l.id,'occurrence_key',occ->>'occurrence_key'))||s.eligibility
  order by s.state_rank,(s.o).actual_start desc,(s.o).id),'[]'),
  case when (select count(*) from page)>page_size then (select jsonb_build_object('version',1,'factory',factory,'occurrence',occ->>'occurrence_key','as_of',evaluated,
   'revision',rev,'schedule_revision',schedule_rev,'page_size',page_size,'context',context_key,'last_state',state_rank,'last_start',(o).actual_start,'last_id',(o).id)
   from selected order by state_rank desc,(o).actual_start,(o).id desc limit 1) end
 into total,rows,next_page from selected s
 join public.products p on p.factory_id=factory and p.id=(s.o).product_id
 join public.production_lines l on l.factory_id=factory and l.id=(s.o).line_id
 left join public.production_requests r on r.factory_id=factory and r.id=(s.o).request_id;
 return ctx||jsonb_build_object('contract_version',3,'factory_id',factory,'server_as_of',stamp,'evaluation_as_of',evaluated,'expires_at',occ->'ends_at',
  'dataset_revision',rev,'schedule_revision',schedule_rev,'context',context_key,'can_edit',can_edit,
  'rows',rows,'total',total,'page_size',page_size,'next_cursor',next_page,'complete',next_page is null,'late_recording_available',false);
exception when invalid_text_representation or invalid_datetime_format or datetime_field_overflow then raise exception 'shift_work_invalid' using errcode='22023';
end$$;

-- All internal helpers are private, even if the API schema exposure changes.
do $$declare fn record;begin for fn in select p.oid::regprocedure signature from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='private' and p.proname in ('production_shift_immutable','shift_boundary_utc','shift_occurrence_descriptor','resolve_production_occurrence',
 'append_production_shift_revision','materialize_production_occurrence','configure_shift_before_occurrences','settings_before_shift_occurrences','seed_production_shift_revision','production_recording_eligibility')
 loop execute format('revoke all on function %s from public,anon,authenticated',fn.signature);end loop;end$$;
revoke all on function public.production_shift_work(uuid,jsonb,integer),public.configure_production_shift(uuid,text,text,time,time,uuid,boolean),private.update_settings(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.production_shift_work(uuid,jsonb,integer),public.configure_production_shift(uuid,text,text,time,time,uuid,boolean),private.update_settings(uuid,text,text,text) to authenticated;
commit;
