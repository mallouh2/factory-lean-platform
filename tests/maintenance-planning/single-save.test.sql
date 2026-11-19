-- Run inside the existing guarded local test environment. All fixture rows roll back.
begin;
do $$
<<save_check>>
declare
  fixture jsonb;
  f uuid;
  r uuid;
  l uuid;
  i uuid;
  machine uuid;
  a timestamptz := date_trunc('minute',now()) + interval '3 days';
  b timestamptz;
  revision integer;
  preview jsonb;
  payload jsonb;
  schedule_id uuid;
  retry_id uuid := gen_random_uuid();
  initial_plan jsonb;
  initial_machine jsonb;
  activation boolean;
begin
  select enabled into activation from private.maintenance_planning_activation;
  if not activation then raise exception 'This confirmation check needs the already active local review environment'; end if;
  fixture := mp_test.fixture('group4-one-save');
  f := (fixture->>'factory')::uuid;
  r := (fixture->>'request')::uuid;
  l := (fixture->>'line')::uuid;
  i := (fixture->>'item')::uuid;
  machine := (fixture->>'machine')::uuid;
  select to_jsonb(o) into initial_plan from public.production_orders o where id=i;
  select to_jsonb(m) into initial_machine from public.work_centers m where id=machine;
  select mr.revision into revision from public.maintenance_requests mr where id=r;
  perform public.maintenance_planning_command(f,r,'details',jsonb_build_object(
    'maintenance_kind','PLANNED','estimated_duration_minutes',30,
    'preferred_start',a + interval '1 hour','preferred_end',a + interval '3 hours'
  ),revision,gen_random_uuid());
  select mr.revision into revision from public.maintenance_requests mr where id=r;
  b := a + interval '30 minutes';
  preview := public.maintenance_planning_preview(f,r,a,b,revision,0,null);
  if preview->>'capacity'<>'CLEAR' then raise exception 'Expected a clear candidate'; end if;
  payload := jsonb_build_object('start',a,'request_revision',revision,'context_hash',preview->>'context_hash');
  begin
    perform public.maintenance_planning_command(f,r,'save',payload,0,retry_id);
    raise exception 'Missing preferred-window reason was accepted';
  exception when others then
    if sqlerrm<>'maintenance_preferred_reason' then raise; end if;
  end;
  if exists(select 1 from public.maintenance_schedules where maintenance_request_id=r) then
    raise exception 'Rejected save left a schedule';
  end if;
  perform set_config('request.jwt.claim.sub',fixture->>'viewer',true);
  begin
    perform public.maintenance_planning_command(f,r,'save',payload||'{"reason":"Team available earlier"}',0,retry_id);
    raise exception 'Unauthorized user scheduled maintenance';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',fixture->>'owner',true);
  payload := payload||'{"reason":"Team available earlier"}';
  perform public.maintenance_planning_command(f,r,'save',payload,0,retry_id);
  perform public.maintenance_planning_command(f,r,'save',payload,0,retry_id);
  select id into schedule_id from public.maintenance_schedules
  where maintenance_request_id=r and state='CONFIRMED' and planned_start=a and planned_end=b and hold_started_at is null;
  if schedule_id is null then raise exception 'Confirmed half-hour window missing'; end if;
  if (select count(*) from public.maintenance_schedule_revisions h
      where h.schedule_id=save_check.schedule_id) <> 1 then raise exception 'Retry changed history'; end if;
  if not exists(select 1 from public.maintenance_schedule_revisions h
      where h.schedule_id=save_check.schedule_id and reason='Team available earlier' and event='confirm') then
    raise exception 'Preferred-window reason missing from history';
  end if;
  if private.maintenance_capacity_conflict(f,l,null,machine,a,b) is null then raise exception 'Capacity was not reserved'; end if;
  if initial_plan is distinct from (select to_jsonb(o) from public.production_orders o where id=i)
    or initial_machine is distinct from (select to_jsonb(m) from public.work_centers m where id=machine)
    or activation is distinct from (select enabled from private.maintenance_planning_activation) then
    raise exception 'Scheduling changed actual state, production planning or activation';
  end if;
  perform public.maintenance_planning_command(f,r,'unschedule','{"reason":"Test requeue"}',1,gen_random_uuid());
  if not exists(select 1 from private.planning_operational_rows(f,a+interval '5 days',a+interval '6 days',null,null,'production_plan',now()) q
    where q.kind='REQUEST' and q.id=r and q.payload->'request'->>'planning_schedule_revision'='2') then
    raise exception 'Requeued work lost its schedule revision outside the old horizon';
  end if;
  preview := public.maintenance_planning_preview(f,r,a,b,revision,2,null);
  payload := jsonb_build_object('start',a,'request_revision',revision,'context_hash',preview->>'context_hash','reason','Team available earlier');
  perform public.plan_product_item(f,i,l,a);
  begin
    perform public.maintenance_planning_command(f,r,'save',payload,2,gen_random_uuid());
    raise exception 'An earlier preview remained valid after a production booking';
  exception when serialization_failure then
    if sqlerrm<>'maintenance_preview_stale' then raise; end if;
  end;
  preview := public.maintenance_planning_preview(f,r,a,b,revision,2,null);
  payload := jsonb_build_object('start',a,'request_revision',revision,'context_hash',preview->>'context_hash','reason','Team available earlier');
  begin
    perform public.maintenance_planning_command(f,r,'save',payload,2,gen_random_uuid());
    raise exception 'Overlapping maintenance was accepted';
  exception when others then
    if sqlerrm<>'maintenance_production_conflict' then raise; end if;
  end;
  if not exists(select 1 from public.maintenance_schedules where id=save_check.schedule_id and state='UNSCHEDULED' and maintenance_schedules.revision=2) then
    raise exception 'Rejected overlap changed the schedule';
  end if;
end $$;
select 'Single-save, advisory reason, retry, permission, queue revision, conflict and preservation checks passed';
rollback;
