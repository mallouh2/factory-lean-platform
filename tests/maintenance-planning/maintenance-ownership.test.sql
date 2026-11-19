-- Caller verifies the identity of the existing local cluster. All fixture rows roll back.
begin;
do $$
declare
  fixture jsonb := mp_test.fixture('group4-maintenance-ownership');
  f uuid := (fixture->>'factory')::uuid;
  r uuid := (fixture->>'request')::uuid;
  equipment uuid := (fixture->>'other_machine')::uuid;
  item uuid := (fixture->>'item')::uuid;
  original_plan jsonb;
  original_equipment jsonb;
  request_revision integer;
  booking uuid;
  a timestamptz := date_trunc('minute',now()) + interval '3 days';
  b timestamptz := a + interval '90 minutes';
  candidate jsonb;
  fields jsonb := jsonb_build_object('work_center_id',equipment,'title','Corrective equipment work','description','New work description',
    'maintenance_kind','CORRECTIVE','estimated_duration_minutes',90,'preferred_start',a+interval '1 hour','preferred_end',b+interval '1 hour');
begin
  select to_jsonb(o) into original_plan from public.production_orders o where o.id=item;
  select to_jsonb(m) into original_equipment from public.work_centers m where m.id=equipment;
  select revision into request_revision from public.maintenance_requests where id=r;
  insert into public.user_permissions(factory_id,user_id,module,action)
  values(f,(fixture->>'viewer')::uuid,'orders','view'),(f,(fixture->>'viewer')::uuid,'orders','edit');
  perform set_config('request.jwt.claim.sub',fixture->>'viewer',true);
  begin
    perform public.maintenance_planning_command(f,r,'details',fields,request_revision,gen_random_uuid());
    raise exception 'Planner could edit Maintenance fields';
  exception when insufficient_privilege then null;
  end;

  -- Maintenance edit alone can prepare the request, but cannot book the line.
  insert into public.user_permissions(factory_id,user_id,module,action)
   values(f,(fixture->>'worker')::uuid,'maintenance','edit'),(f,(fixture->>'worker')::uuid,'maintenance','view');
  perform set_config('request.jwt.claim.sub',fixture->>'worker',true);
  perform public.maintenance_planning_command(f,r,'details',fields,request_revision,gen_random_uuid());
  select revision into request_revision from public.maintenance_requests where id=r;
  perform public.change_maintenance_request(f,r,'priority','{"priority":"URGENT"}',request_revision,gen_random_uuid());
  select revision into request_revision from public.maintenance_requests where id=r;
  if not exists(select 1 from public.maintenance_requests q where q.id=r and q.work_center_id=equipment and
    q.line_id=(fixture->>'other_line')::uuid and q.description='New work description' and
    q.maintenance_kind='CORRECTIVE' and q.priority='URGENT' and q.estimated_duration_minutes=90) then
    raise exception 'Maintenance fields or urgency were not saved';
  end if;
  begin
    perform public.maintenance_planning_command(f,r,'save','{}',0,gen_random_uuid());
    raise exception 'Maintenance-only staff could reserve Planning capacity';
  exception when insufficient_privilege then null;
  end;

  perform set_config('request.jwt.claim.sub',fixture->>'viewer',true);
  candidate := public.maintenance_planning_preview(f,r,a,b,request_revision,0,null);
  if candidate->>'capacity'<>'CLEAR' then raise exception 'Prepared corrective work was not a valid candidate'; end if;
  begin
    perform public.maintenance_planning_command(f,r,'save',jsonb_build_object('start',a,'context_hash',candidate->>'context_hash',
      'request_revision',request_revision),0,gen_random_uuid());
    raise exception 'An outside-window booking was saved without a reason';
  exception when others then
    if sqlerrm<>'maintenance_preferred_reason' then raise; end if;
  end;
  perform public.maintenance_planning_command(f,r,'save',jsonb_build_object('start',a,'context_hash',candidate->>'context_hash',
    'request_revision',request_revision,'reason','Coordinated with the shift'),0,gen_random_uuid());
  select id into booking from public.maintenance_schedules where maintenance_request_id=r and state='CONFIRMED' and planned_end=b and hold_started_at is null;
  if booking is null then raise exception 'Corrective window was not reserved for the estimate'; end if;
  if (select status from public.maintenance_requests where id=r)<>'ASSIGNED'
   or original_plan is distinct from (select to_jsonb(o) from public.production_orders o where id=item)
   or original_equipment is distinct from (select to_jsonb(m) from public.work_centers m where m.id=equipment) then
    raise exception 'Urgency or scheduling changed actual operations or the production plan';
  end if;
  perform set_config('request.jwt.claim.sub',fixture->>'worker',true);
  begin
    perform public.maintenance_planning_command(f,r,'details',fields,request_revision,gen_random_uuid());
    raise exception 'Maintenance could alter equipment on a confirmed reservation';
  exception when others then
    if sqlerrm<>'maintenance_details_locked' then raise; end if;
  end;
  begin
    perform public.change_maintenance_request(f,r,'start','{}',request_revision,gen_random_uuid());
    raise exception 'Corrective reservation bypassed early-start guard';
  exception when others then
    if sqlerrm<>'maintenance_early_start' then raise; end if;
  end;
end $$;
select 'Corrective booking, Maintenance ownership, urgency, reservation protection and unchanged actual state passed';
rollback;
