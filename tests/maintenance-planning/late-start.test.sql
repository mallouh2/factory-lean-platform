-- Existing identity-verified local cluster only. These fixtures roll back.
begin;
do $$
declare
  x jsonb := mp_test.fixture('safe-late-start');
  f uuid := (x->>'factory')::uuid;
  r uuid := (x->>'request')::uuid;
  machine uuid := (x->>'machine')::uuid;
  item uuid := (x->>'item')::uuid;
  a timestamptz := clock_timestamp()+interval '2 seconds';
  b timestamptz := a+interval '1 minute';
  sid uuid;
  preview jsonb;
  machine_before jsonb;
  order_before jsonb;
  intent uuid := gen_random_uuid();
begin
  if not (select enabled from private.maintenance_planning_activation) then
    raise exception 'Requires the already active review gate';
  end if;
  sid:=mp_test.plan(x,a,b);
  perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
  preview:=public.maintenance_start_context(f,r);
  if preview->>'blocker' is distinct from 'maintenance_early_start' then raise exception 'Early start guard lost'; end if;
  select to_jsonb(m) into machine_before from public.work_centers m where m.id=machine;
  select to_jsonb(o) into order_before from public.production_orders o where o.id=item;
  if (select private.maintenance_start_blocker(q,s,b+interval '1 second')
      from public.maintenance_requests q join public.maintenance_schedules s on s.maintenance_request_id=q.id where q.id=r)
      is not null then raise exception 'A free missed window was treated as a conflict'; end if;
  perform pg_sleep(2.1);
  perform set_config('request.jwt.claim.sub',x->>'viewer',true);
  begin
    perform public.change_maintenance_request(f,r,'start','{}',2,intent);
    raise exception 'Viewer started maintenance';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',x->>'worker',true);
  -- A fresh statement_timing context is used by the live API. The write guard
  -- must evaluate the actual clock after locking even inside this test block.
  perform public.change_maintenance_request(f,r,'start','{}',2,intent);
  perform public.change_maintenance_request(f,r,'start','{}',2,intent);
  if not exists(select 1 from public.maintenance_schedules s join public.maintenance_requests q on q.id=r
    where s.id=sid and s.planned_start=a and s.planned_end=b and s.hold_started_at=q.started_at
      and q.started_at>a and q.status='IN_PROGRESS') then
    raise exception 'Safe late start did not preserve plan and record actual';
  end if;
  if (select count(*) from public.maintenance_schedule_revisions where schedule_id=sid and event='start'
      and reason like '%Start deviation:%Estimated overrun:%')<>1 then raise exception 'Start variance audit missing or duplicated'; end if;
  perform public.change_maintenance_request(f,r,'complete','{"work_note":"Rollback-only repair completed"}',3,gen_random_uuid());
  if not exists(select 1 from public.audit_logs where factory_id=f and entity='maintenance_requests' and entity_id=r
    and new_data->>'completed_at' is not null and new_data->>'status'='COMPLETED') then
    raise exception 'Actual completion time missing in audit';
  end if;
  if (select released_at from public.maintenance_schedules where id=sid) is not null then raise exception 'Completion released before verification'; end if;
  if machine_before is distinct from (select to_jsonb(m) from public.work_centers m where m.id=machine)
     or order_before is distinct from (select to_jsonb(o) from public.production_orders o where o.id=item) then
    raise exception 'Maintenance execution changed machine status or production plan';
  end if;
end $$;

do $$
declare
  x jsonb := mp_test.fixture('late-start-conflict');
  f uuid := (x->>'factory')::uuid;
  r uuid := (x->>'request')::uuid;
  i uuid := (x->>'item')::uuid;
  a timestamptz := clock_timestamp()+interval '2 seconds';
  b timestamptz := a+interval '1 minute';
  sid uuid;
  context jsonb;
  plan jsonb;
begin
  sid:=mp_test.plan(x,a,b);
  perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
  -- The order begins exactly at the confirmed reservation end. It conflicts
  -- only with the projected overrun, not with the approved maintenance slot.
  perform public.plan_product_item(f,i,(x->>'line')::uuid,b);
  select to_jsonb(o) into plan from public.production_orders o where o.id=i;
  perform pg_sleep(2.1);
  perform set_config('request.jwt.claim.sub',x->>'worker',true);
  begin
    perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
    raise exception 'Start ignored planned production in its forecast overrun';
  exception when others then
    if sqlerrm<>'maintenance_production_conflict' then raise; end if;
  end;
  if (select hold_started_at is not null from public.maintenance_schedules where id=sid)
    or plan is distinct from (select to_jsonb(o) from public.production_orders o where o.id=i) then
    raise exception 'Blocked start changed reservation or production';
  end if;
  -- When checking after the approved interval, the helper still detects a
  -- genuine overlapping booking rather than treating the elapsed slot as free.
  if (select private.maintenance_start_blocker(q,s,b+interval '1 second')
      from public.maintenance_requests q join public.maintenance_schedules s on s.maintenance_request_id=q.id where q.id=r)
      is distinct from 'maintenance_production_conflict' then raise exception 'Missed-window conflict lost'; end if;
  perform set_config('request.jwt.claim.sub',x->>'owner',true);
  perform set_config('factory_lean.test_late_context',jsonb_build_object('factory',f,'request',r,'item',i)::text,true);
end $$;

do $$
declare x jsonb:=current_setting('factory_lean.test_late_context')::jsonb; context jsonb;begin
 context:=public.maintenance_start_context((x->>'factory')::uuid,(x->>'request')::uuid);
 if context->>'blocker' is distinct from 'maintenance_production_conflict'
    or coalesce((context->>'overrun_seconds')::numeric,0)<=0 or jsonb_array_length(context->'affected')<>1
    or nullif(context->'affected'->0->>'code','') is null then
   raise exception 'Advisory preview did not show the affected order and expected overrun: %',context;
 end if;
end $$;
select 'Late-start, affected-work, permissions, conflict, audit, and plan-preservation checks passed';
rollback;
