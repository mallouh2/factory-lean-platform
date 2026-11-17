-- Group 2: execution owns automatic Running/Idle; legitimate downtime survives.
create function private.machine_has_active_work(f uuid,w uuid,l uuid,i uuid)
returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.production_orders o where o.factory_id=f
 and o.id=private.execution_center_order(f,w,l,i) and o.status='active')
$$;
revoke all on function private.machine_has_active_work(uuid,uuid,uuid,uuid)from public,anon,authenticated,service_role;

create or replace function private.project_center_execution()returns trigger
language plpgsql security definer set search_path=''as $$begin
 new.order_id:=private.execution_center_order(new.factory_id,new.id,new.line_id,new.order_id);
 if new.status='running'and not private.machine_has_active_work(new.factory_id,new.id,new.line_id,new.order_id)then
 raise exception 'execution_no_active_work'using errcode='22023';end if;
 if new.status='running'and exists(select 1 from public.production_lines l where l.factory_id=new.factory_id
 and l.id=coalesce((select o.line_id from public.production_orders o where o.factory_id=new.factory_id and o.id=new.order_id),new.line_id)and l.paused_at is not null)then
 raise exception 'line_paused'using errcode='22023';end if;
 return new;end$$;

create or replace function private.project_item_execution()returns trigger
language plpgsql security definer set search_path=''as $$
declare c public.work_centers;assigned uuid;next_status text;begin
 if old.status is not distinct from new.status then return new;end if;
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 for c in select *from public.work_centers where factory_id=new.factory_id
 and(line_id=new.line_id or order_id=new.id)order by id for update loop
 assigned:=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id);
 next_status:=c.status;
 if c.status='running'and not private.machine_has_active_work(c.factory_id,c.id,c.line_id,assigned)then next_status:='idle';
 elsif c.status='idle'and not c.archived and private.machine_has_active_work(c.factory_id,c.id,c.line_id,assigned)
 and not exists(select 1 from public.production_lines l where l.factory_id=c.factory_id and l.id=c.line_id and l.paused_at is not null
 and not exists(select 1 from public.production_transfers t where t.factory_id=c.factory_id and t.alternative_id=c.id and t.ended_at is null))
 and not exists(select 1 from public.downtime_events d where d.factory_id=c.factory_id and d.work_center_id=c.id and d.ended_at is null)
 then next_status:='running';end if;
 if(c.order_id,c.status)is distinct from(assigned,next_status)then
 update public.work_centers set order_id=assigned,status=next_status,updated_at=clock_timestamp(),
 last_restart_time=case when next_status='running'and c.status<>'running'then clock_timestamp()else last_restart_time end where id=c.id;
 if c.status<>next_status then insert into public.status_events(factory_id,work_center_id,old_status,new_status,notes,created_by)
 values(c.factory_id,c.id,c.status,next_status,'Execution status synchronization',auth.uid());end if;
 end if;end loop;return new;end$$;

-- Role/capability configuration is authoritative; the operator confirms, never overrides.
create function private.machine_required_for_work(f uuid,w uuid,i uuid)returns boolean
language sql stable security definer set search_path=''as $$
 select coalesce((select(c.dependency_mode in('blocking','buffer')and c.impact_scope<>'none')
 or exists(select 1 from public.production_orders o join public.production_routing_steps rs
 on rs.factory_id=o.factory_id and rs.product_id=o.product_id and rs.kind='work_center'
 where o.factory_id=f and o.id=i and rs.work_center_id=c.id)
 from public.work_centers c where c.factory_id=f and c.id=w),false)
$$;
revoke all on function private.machine_required_for_work(uuid,uuid,uuid)from public,anon,authenticated,service_role;

create function public.stop_machine_with_impact(factory uuid,work_center uuid,nature text,reason uuid,activity text,
 affects_production boolean,notes text default '',maintenance jsonb default null)returns uuid language plpgsql security definer set search_path=''as $$
declare c public.work_centers;event_id uuid;prior_impact boolean;begin
 if not private.has_permission(factory,'centers','edit')then perform private.require_permission(factory,'machine_status','edit');end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 -- Preserve the original linked-stop actor/intent replay before evaluating a
 -- later machine configuration. The confirmed impact is bound to that event.
 if maintenance is not null and exists(select 1 from public.maintenance_commands mc where mc.factory_id=factory and mc.request_id=(maintenance->>'request_id')::uuid)then
 select d.blocking_at_start into prior_impact from public.maintenance_stop_associations a join public.downtime_events d
 on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=factory and a.request_id=(maintenance->>'request_id')::uuid limit 1;
 if affects_production is distinct from prior_impact then raise exception 'request_conflict';end if;
 return public.stop_machine_for_maintenance(factory,work_center,nature,reason,activity,notes,
 (maintenance->>'schedule')::uuid,(maintenance->>'expected_revision')::integer,(maintenance->>'expected_request_revision')::integer,(maintenance->>'request_id')::uuid);
 end if;
 select *into c from public.work_centers where factory_id=factory and id=work_center and not archived for update;
 if c.id is null then raise exception 'not_found';end if;
 if affects_production is distinct from private.machine_required_for_work(factory,c.id,private.execution_center_order(factory,c.id,c.line_id,c.order_id))then
 raise exception 'machine_impact_conflict'using errcode='22023';end if;
 if maintenance is null then event_id:=public.stop_machine(factory,work_center,nature,reason,activity,notes);
 else
 if jsonb_typeof(maintenance)<>'object'or exists(select 1 from jsonb_object_keys(maintenance)k where k not in('schedule','expected_revision','expected_request_revision','request_id'))then raise exception 'invalid_notes';end if;
 event_id:=public.stop_machine_for_maintenance(factory,work_center,nature,reason,activity,notes,
 (maintenance->>'schedule')::uuid,(maintenance->>'expected_revision')::integer,(maintenance->>'expected_request_revision')::integer,(maintenance->>'request_id')::uuid);
 end if;
 return event_id;end$$;
revoke all on function public.stop_machine_with_impact(uuid,uuid,text,uuid,text,boolean,text,jsonb)from public,anon,authenticated,service_role;
grant execute on function public.stop_machine_with_impact(uuid,uuid,text,uuid,text,boolean,text,jsonb)to authenticated;

create function private.execution_machine_readiness(f uuid,i uuid,l uuid,p uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare c public.work_centers;e public.work_centers;t public.production_transfers;begin
 for c in select *from public.work_centers where factory_id=f and not archived and(line_id=l
 or id in(select work_center_id from public.production_routing_steps where factory_id=f and product_id=p and kind='work_center'))order by id loop
 if not private.machine_required_for_work(f,c.id,i)then continue;end if;
 e:=c;
 select *into t from public.production_transfers where factory_id=f and original_id=c.id and ended_at is null;
 if t.id is not null and t.order_id=i then select *into e from public.work_centers where factory_id=f and id=t.alternative_id and category_id=c.category_id and not archived;end if;
 if e.id is null or e.status not in('running','idle')or exists(select 1 from public.downtime_events d where d.factory_id=f and d.work_center_id=e.id and d.ended_at is null)
 or exists(select 1 from public.production_transfers x where x.factory_id=f and x.alternative_id=e.id and x.ended_at is null and x.order_id<>i)then
 return jsonb_build_object('ready',false,'applicable',true,'reason','MACHINE_STOPPED','machine',to_jsonb(e));end if;
 end loop;return jsonb_build_object('ready',true,'applicable',true,'reason',null,'machine',null);end$$;
revoke all on function private.execution_machine_readiness(uuid,uuid,uuid,uuid)from public,anon,authenticated,service_role;

create function private.execution_machine_start_guard()returns trigger language plpgsql security definer set search_path=''as $$
declare check_result jsonb;begin
 if new.status='active'and old.status<>'active'then
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text||':structure',0));
 check_result:=private.execution_machine_readiness(new.factory_id,new.id,new.line_id,new.product_id);
 if not(check_result->>'ready')::boolean then raise exception 'execution_machine_stopped'using errcode='22023';end if;
 -- No active work existed on this line; a stale idle pause must not survive a new explicit Start.
 update public.production_lines set paused_at=null,pause_reason=null where factory_id=new.factory_id and id=new.line_id and paused_at is not null;
 delete from private.line_pause_auto_idled where factory_id=new.factory_id and line_id=new.line_id;
 end if;return new;end$$;
revoke all on function private.execution_machine_start_guard()from public,anon,authenticated,service_role;
create trigger b_execution_machine_start before update of status on public.production_orders
for each row execute function private.execution_machine_start_guard();
create function private.reconcile_execution_machine_status(f uuid)returns integer
language plpgsql security definer set search_path=''as $$
declare c public.work_centers;n integer:=0;next_status text;begin
 perform private.require_permission(f,'centers','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform private.maintenance_planning_lock(f);
 for c in select *from public.work_centers where factory_id=f and not archived order by id for update loop
 next_status:=c.status;
 if c.status='running'and not private.machine_has_active_work(f,c.id,c.line_id,c.order_id)then next_status:='idle';
 elsif c.status='idle'and private.machine_has_active_work(f,c.id,c.line_id,c.order_id)
 and not exists(select 1 from public.downtime_events d where d.factory_id=f and d.work_center_id=c.id and d.ended_at is null)
 and not exists(select 1 from public.production_lines l where l.factory_id=f and l.id=c.line_id and l.paused_at is not null
 and not exists(select 1 from public.production_transfers t where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null))then next_status:='running';end if;
 if next_status<>c.status then
 update public.work_centers set status=next_status,updated_at=clock_timestamp(),last_restart_time=case when next_status='running'then clock_timestamp()else last_restart_time end where id=c.id;
 insert into public.status_events(factory_id,work_center_id,old_status,new_status,notes,created_by)values(f,c.id,c.status,next_status,'Group 2 execution status reconciliation',auth.uid());n:=n+1;
 end if;end loop;return n;end$$;
revoke all on function private.reconcile_execution_machine_status(uuid)from public,anon,authenticated,service_role;

-- Existing protected command extensions.
CREATE OR REPLACE FUNCTION private.set_line_pause(f uuid, l uuid, paused boolean, reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare idled_ids uuid[]; restored_ids uuid[];
begin
 perform private.require_permission(f,'centers','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform private.maintenance_planning_lock(f);
 if not exists(select 1 from public.production_orders where factory_id=f and line_id=l and status='active')then raise exception 'execution_line_idle'using errcode='22023';end if;
 if paused is null or (paused and reason not in
   ('borrow_machine','planned_stop','cleaning','changeover','no_production','other')) then
  raise exception 'invalid_pause_reason';
 end if;
 perform 1 from public.production_lines
 where id=l and factory_id=f and not archived for update;
 if not found then raise exception 'not_found'; end if;

 if paused then
  update public.production_lines
  set paused_at=coalesce(paused_at,now()),pause_reason=reason
  where id=l;

  -- An already borrowed machine belongs to its open transfer, not this line's
  -- physical pause. All other running home machines become available idle.
  with idled as (
   update public.work_centers c
   set status='idle',updated_at=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='running'
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
   )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into idled_ids from idled;

  -- Run this after the UPDATE's status triggers, which clear old markers.
  insert into private.line_pause_auto_idled(factory_id,line_id,work_center_id)
  select f,l,id from unnest(idled_ids) id;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'running','idle',auth.uid() from unnest(idled_ids) id;
 else
  update public.production_lines
  set paused_at=null,pause_reason=null
  where id=l;

  -- Lock centers before reading their markers. A concurrent manual status
  -- change either finishes first and removes its marker, or follows Resume.
  perform 1 from public.work_centers c
  where c.factory_id=f and c.line_id=l
    and exists (
     select 1 from private.line_pause_auto_idled m
     where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
    )
  order by c.id for update;

  with restored as (
   update public.work_centers c
   set status='running',updated_at=now(),last_restart_time=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='idle'
     and exists (
      select 1 from private.line_pause_auto_idled m
      where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
     )
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
     )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into restored_ids from restored;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'idle','running',auth.uid() from unnest(restored_ids) id;

  -- A pause is finished even if a machine was borrowed or manually changed.
  delete from private.line_pause_auto_idled where factory_id=f and line_id=l;
 end if;
end$function$
;
CREATE OR REPLACE FUNCTION public.finish_product_item(factory uuid, item uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare target public.production_orders%rowtype;
begin
  perform private.require_permission(factory,'orders','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
  -- Lock before item/center rows, shared with transfer and layout operations.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(factory::text||':structure',0));
  select * into target from public.production_orders
    where factory_id=factory and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status <> 'active' or target.actual_start is null
    or target.actual_finish is not null then
    raise exception 'execution_not_running';
  end if;
  update public.production_orders set status='completed',
    actual_finish=pg_catalog.clock_timestamp()
    where factory_id=factory and id=item;
  return item;
end;
$function$
;
CREATE OR REPLACE FUNCTION private.change_status(f uuid, w uuid, s text, reason uuid, sub_reason uuid, n text, eta timestamp with time zone, responsible uuid, alternative uuid, transferred boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if not private.has_permission(f,'centers','edit') then perform private.require_permission(f,'machine_status','edit');end if;
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform private.maintenance_planning_lock(f);
 if s='running'and not exists(select 1 from public.work_centers c where c.factory_id=f and c.id=w
 and private.machine_has_active_work(f,c.id,c.line_id,c.order_id))then raise exception 'execution_no_active_work'using errcode='22023';end if;
 perform private.maintenance_status_base(f,w,s,reason,sub_reason,n,eta,responsible,alternative,transferred);
end$function$;
CREATE OR REPLACE FUNCTION private.capture_stop_context()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  machine public.work_centers%rowtype;
  borrowed_line uuid;
  borrowed_item uuid;
begin
  -- Current assignment is not trustworthy context for a missed historical stop.
  if new.retroactive then return new; end if;
  select * into machine from public.work_centers
    where factory_id=new.factory_id and id=new.work_center_id;
  select source.line_id, transfer.order_id into borrowed_line, borrowed_item
    from public.production_transfers transfer
    join public.work_centers source
      on source.factory_id=transfer.factory_id and source.id=transfer.original_id
    where transfer.factory_id=new.factory_id
      and transfer.alternative_id=new.work_center_id and transfer.ended_at is null
    order by transfer.created_at desc limit 1;
  if found then
    new.line_id:=borrowed_line;
    new.order_id:=borrowed_item;
  else
    new.line_id:=machine.line_id;
    new.order_id:=machine.order_id;
  end if;
  new.impact_scope_at_start:=machine.impact_scope;
  new.blocking_at_start:=private.machine_required_for_work(new.factory_id,machine.id,new.order_id);
 if new.blocking_at_start and new.impact_scope_at_start='none'then new.impact_scope_at_start:='whole_line';end if;
  new.buffer_minutes_at_start:=case when machine.dependency_mode='buffer'
    then machine.buffer_minutes else 0 end;
  new.rate_at_start:=machine.production_speed;
  return new;
end;
$function$
;
CREATE OR REPLACE FUNCTION public.production_start_readiness(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;physical jsonb;hold jsonb;blocker jsonb;stamp timestamptz;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 select * into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found' using errcode='P0002';end if;
 physical:=private.maintenance_execution_readiness(factory,o.id,o.line_id,o.product_id);
 if coalesce((physical->>'ready')::boolean,true)then physical:=private.execution_machine_readiness(factory,o.id,o.line_id,o.product_id);end if;
 stamp:=clock_timestamp();
 -- This is current maintenance occupancy, not a new duration/calendar engine.
 -- The original Start trigger still checks both plan and intended execution span.
 hold:=private.maintenance_capacity_conflict(factory,o.line_id,o.product_id,null,stamp,stamp+interval '1 microsecond',null,o.id,false);
 if hold is not null then
 select jsonb_build_object('reason','MAINTENANCE_HOLD','machine',jsonb_build_object('id',c.id,'code',c.code,'name',c.name,'name_ar',c.name_ar,'status',c.status))
 into blocker from public.maintenance_schedule_resources r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where r.factory_id=factory and r.schedule_id=(hold->>'schedule')::uuid and r.resource_kind='MACHINE' order by c.id limit 1;
 end if;
 return jsonb_build_object('factory',factory,'item',item,'physical',physical,'materials',private.material_start_readiness(factory,item),'maintenance_block',blocker,
 'quality_hold',private.output_work_held(factory,item),'evaluated_at',stamp,'queue_ready',coalesce(o.status='planned' and o.actual_start is null and o.actual_finish is null
 and o.start_time is not null and o.expected_finish>o.start_time
 and not exists(select 1 from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='active')
 and o.id=(select x.id from public.production_orders x where x.factory_id=factory and x.line_id=o.line_id and x.status='planned'
 and x.actual_start is null and x.actual_finish is null and x.start_time is not null and x.expected_finish>x.start_time order by x.start_time,x.id limit 1),false));
end$function$;
