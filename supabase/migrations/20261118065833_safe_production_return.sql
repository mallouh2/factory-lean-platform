-- F48 reuses current execution, recovery, reservation and audit authority.
CREATE OR REPLACE FUNCTION private.guard_execution_destination()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 if tg_op='INSERT'then if new.actual_line_id is not null then raise exception 'execution_use_command';end if;return new;end if;
 if private.execution_command_allowed(old.factory_id,old.id,array['TRANSFER_LINE','RETURN_PRODUCTION'])then
  if row(new.line_id,new.start_time,new.expected_finish)is distinct from row(old.line_id,old.start_time,old.expected_finish)then raise exception 'execution_plan_immutable';end if;
 elsif row(new.line_id,new.start_time,new.expected_finish)is distinct from row(old.line_id,old.start_time,old.expected_finish)and old.status='planned'then
  -- An explicit authorized Planning revision may choose the next execution route.
  -- Existing Planning guards still validate that change; old runs retain their routes.
  new.actual_line_id:=null;
 elsif new.actual_line_id is distinct from old.actual_line_id then raise exception 'execution_use_command';end if;
 return new;end$function$
;
CREATE OR REPLACE FUNCTION private.execution_effective_center(f uuid, i uuid, w uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;c record;effective uuid:=w;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.actual_line_id is null then return w;end if;
 for c in select case when operation='RETURN_PRODUCTION' then intent||jsonb_build_object('source_machine',intent->'alternative_machine','alternative_machine',intent->'source_machine')else intent end intent from private.production_execution_commands where factory_id=f and item_id=i and (operation='TRANSFER_LINE'or operation='RETURN_PRODUCTION'and before_state->>'return_mode'='LINE')
 and result->>'outcome'is distinct from 'REJECTED'order by started_at,request_id loop
  if (c.intent->>'source_machine')::uuid=effective then effective:=(c.intent->>'alternative_machine')::uuid;end if;
 end loop;return effective;end$function$
;
CREATE OR REPLACE FUNCTION private.refresh_production_stock(f uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o record;forecast jsonb;resolved jsonb;stamp timestamptz;x jsonb;needed numeric;free numeric;booked numeric;begin
 if not private.production_stock_enabled(f)then return;end if;perform private.production_stock_lock(f);
 update private.production_stock_reservations set reserved=0 where factory_id=f and reserved<>0 and not exists(select 1 from public.production_orders held where held.factory_id=f and held.id=production_stock_reservations.item_id and held.status='planned'and private.execution_command_allowed(f,held.id,array['TRANSFER_LINE','RETURN_PRODUCTION'])and not exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=held.id and r.state='ARMED'));
 for o in select id from public.production_orders where factory_id=f and status in('active','planned')and line_id is not null and start_time is not null
 and not(status='planned'and private.execution_command_allowed(f,id,array['TRANSFER_LINE','RETURN_PRODUCTION'])and not exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED'))
 and(execution_interrupted_at is null or exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED'))
 order by(status='active')desc,exists(select 1 from private.production_execution_runs r where r.factory_id=f and r.item_id=production_orders.id and r.state='ARMED')desc,start_time,id loop
 if not private.production_stock_eligible(f,o.id)then continue;end if;
 if resolved is null then stamp:=clock_timestamp();resolved:=private.resolve_production_occurrence(f,stamp);end if;
 forecast:=private.production_stock_forecast(f,o.id,stamp,resolved);if forecast->>'warning'is not null then continue;end if;
 insert into private.production_stock_orders(factory_id,item_id)values(f,o.id)on conflict do nothing;
 for x in select value from jsonb_array_elements(forecast->'inputs')loop
 needed:=(x->>'quantity')::numeric;
 free:=greatest(private.production_stock_quantity(f,(x->>'id')::uuid)-private.production_stock_return_pending(f,(x->>'id')::uuid)-coalesce((select sum(reserved)from private.production_stock_reservations where factory_id=f and material_id=(x->>'id')::uuid),0),0);
 booked:=least(needed,free);
 insert into private.production_stock_reservations(factory_id,item_id,occurrence_key,material_id,required,reserved,expected_output,evidence)
 values(f,o.id,forecast#>>'{occurrence,occurrence_key}',(x->>'id')::uuid,needed,booked,(forecast->>'expected_output')::numeric,forecast)
 on conflict(factory_id,item_id,occurrence_key,material_id)do update set required=excluded.required,reserved=excluded.reserved,expected_output=excluded.expected_output,evidence=excluded.evidence,updated_at=clock_timestamp();
 end loop;end loop;
 -- Reservations are a derived current projection; physical postings, confirmed
 -- requests and handover snapshots retain audit without logging every clock tick.
 end$function$
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
 if s='running'and exists(select 1 from public.production_transfers t where t.factory_id=f and t.original_id=w and t.ended_at is null and not private.execution_command_allowed(f,t.order_id,array['RETURN_PRODUCTION']))then raise exception 'f48UseReturn'using errcode='22023';end if;
 if s='running'and not exists(select 1 from public.work_centers c where c.factory_id=f and c.id=w
 and private.machine_has_active_work(f,c.id,c.line_id,c.order_id))then raise exception 'execution_no_active_work'using errcode='22023';end if;
 perform private.maintenance_status_base(f,w,s,reason,sub_reason,n,eta,responsible,alternative,transferred);
end$function$
;
CREATE OR REPLACE FUNCTION private.transfer_production(f uuid, w uuid, a uuid, n text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o uuid;d uuid;i uuid;previous_order uuid;
begin
 perform private.require_permission(f,'centers','edit');
 perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform private.maintenance_planning_lock(f);
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.work_centers where factory_id=f and id in (w,a) order by id for update;
 select order_id into o from public.work_centers
 where id=w and factory_id=f and not archived and status='stopped';
 select id into d from public.downtime_events
 where work_center_id=w and factory_id=f and ended_at is null;
 if o is null or d is null or not exists(
  select 1 from public.production_orders where id=o and status='active'
 ) then raise exception 'invalid_order'; end if;
 if exists(select 1 from public.production_transfers
   where factory_id=f and original_id=w and ended_at is null)
 then raise exception 'transfer_already_active'; end if;
 if not exists(
   select 1 from public.work_center_alternatives
   where factory_id=f and work_center_id=w and alternative_id=a
 ) or not exists(
   select 1 from public.work_centers c
   left join public.production_lines home
     on home.id=c.line_id and home.factory_id=f and not home.archived
   where c.id=a and c.factory_id=f and not c.archived and c.status='idle'
     and (c.order_id is null or c.order_id=o or home.paused_at is not null)
 ) or (select category_id from public.work_centers where id=w)
      is distinct from (select category_id from public.work_centers where id=a)
   or not exists(
     select 1 from public.work_center_capabilities cap
     join public.production_orders job on job.factory_id=cap.factory_id
       and job.product_id=cap.product_id
     where cap.factory_id=f and cap.work_center_id=a and job.id=o
       and cap.rate>0 and cap.rate_unit=job.unit
   )
   or exists(
     select 1 from public.production_transfers
     where factory_id=f and alternative_id=a and ended_at is null
   )
 then raise exception 'incompatible_alternative'; end if;
 select order_id into previous_order
 from public.work_centers where id=a and factory_id=f;
 insert into public.production_transfers(
  factory_id,original_id,alternative_id,order_id,downtime_id,reason,
  created_by,alternative_previous_order_id,alternative_order_captured
 ) values(f,w,a,o,d,n,auth.uid(),previous_order,true) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;
end$function$
;
CREATE OR REPLACE FUNCTION public.production_execution_context(factory uuid, item uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.production_orders;h jsonb;begin
 perform private.require_permission(factory,'orders','view');
 select *into o from public.production_orders where factory_id=factory and id=item;
 if not found then raise exception 'not_found';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'line_id',r.line_id,'started_at',r.started_at,'ended_at',r.ended_at,
 'start_variance_seconds',extract(epoch from(r.started_at-(r.planned->>'start')::timestamptz))::text,'end_variance_seconds',case when r.ended_at is not null then extract(epoch from(r.ended_at-(r.planned->>'finish')::timestamptz))::text end,'state',r.state,'reason',r.reason,'start_reason',(select c.reason from private.production_execution_commands c where c.factory_id=r.factory_id and c.request_id=r.request_id),'start_actor',r.start_actor,'end_actor',r.end_actor,'planned',r.planned,
 'effective_start',r.effective_start,'effective_finish',r.effective_finish,'recorded_before',r.recorded_before,'recorded_after',r.recorded_after)
 order by r.started_at desc),'[]')into h from private.production_execution_runs r where r.factory_id=factory and r.item_id=item;
 return jsonb_build_object('factory',factory,'item',item,'order',to_jsonb(o),'fingerprint',private.execution_fingerprint(factory,item),'history',h,
 'remaining',private.ordinary_output_remaining(factory,item)::text,'reason_required',private.execution_reason_required(factory,item),'bypassed_order',private.execution_bypassed_order(factory,item),'return_transfers',(select coalesce(jsonb_agg(c.result->'return_transfer' order by c.started_at desc),'[]')from private.production_execution_commands c where c.factory_id=factory and c.item_id=item and c.operation='RETURN_PRODUCTION'and c.result?'return_transfer'),'line_transfers',(select coalesce(jsonb_agg(jsonb_build_object('request_id',c.request_id,'actor',c.actor,'reason',c.reason,'started_at',c.started_at,'source_line',c.before_state->'source_line','destination_line',c.before_state->'destination_line','source_machine',c.before_state->'source_machine','alternative_machine',c.before_state->'alternative_machine','source_downtime',c.before_state->'source_downtime','source_run',c.before_state->'source_run')order by c.started_at desc),'[]')from private.production_execution_commands c where c.factory_id=factory and c.item_id=item and c.operation='TRANSFER_LINE'and c.result->>'outcome'is distinct from 'REJECTED'));
end$function$
;
-- A recovery/physical handover is an actual operation, never a Planning edit.
create function private.production_return_state(f uuid,w uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare t public.production_transfers;c private.production_execution_commands;o public.production_orders;original public.work_centers;alternative public.work_centers;l public.production_lines;
 mode text;reference uuid;stop_id uuid;blocked text;materials jsonb;remaining numeric;rate numeric;fastest numeric;n integer;typed integer;setup integer;finish_at timestamptz;v jsonb;fingerprint text;begin
 select *into t from public.production_transfers where factory_id=f and ended_at is null and w in(original_id,alternative_id);
 if found then mode:='MACHINE';reference:=t.id;stop_id:=t.downtime_id;select *into o from public.production_orders where factory_id=f and id=t.order_id;
  select *into original from public.work_centers where factory_id=f and id=t.original_id;select *into alternative from public.work_centers where factory_id=f and id=t.alternative_id;
 else
  select cmd.*into c from private.production_execution_commands cmd join public.production_orders po on po.factory_id=cmd.factory_id and po.id=cmd.item_id
  where cmd.factory_id=f and cmd.operation='TRANSFER_LINE'and cmd.result is not null and cmd.result->>'outcome'is distinct from 'REJECTED'
  and po.status='active'and po.actual_line_id=(cmd.before_state->>'destination_line')::uuid
  and w in((cmd.before_state->>'source_machine')::uuid,(cmd.before_state->>'alternative_machine')::uuid)
  and not exists(select 1 from private.production_execution_commands later where later.factory_id=f and later.item_id=cmd.item_id
   and later.operation in('TRANSFER_LINE','RETURN_PRODUCTION')and later.result is not null and later.result->>'outcome'is distinct from 'REJECTED'
   and(later.operation='TRANSFER_LINE'or later.before_state->>'return_mode'='LINE')and(later.started_at,later.request_id)>(cmd.started_at,cmd.request_id))
  order by cmd.started_at desc,cmd.request_id desc limit 1;
  if not found then return jsonb_build_object('factory',f,'work_center',w,'available',false);end if;
  mode:='LINE';reference:=c.request_id;stop_id:=(c.before_state->>'source_downtime')::uuid;
  select *into o from public.production_orders where factory_id=f and id=c.item_id;
  select *into original from public.work_centers where factory_id=f and id=(c.before_state->>'source_machine')::uuid;
  select *into alternative from public.work_centers where factory_id=f and id=(c.before_state->>'alternative_machine')::uuid;
 end if;
 select *into l from public.production_lines where factory_id=f and id=original.line_id;remaining:=private.ordinary_output_remaining(f,o.id);
 if o.status<>'active'or o.actual_finish is not null or remaining<=0 then blocked:='execution_no_remaining';
 elsif original.id is null or alternative.id is null or original.archived or alternative.archived or original.category_id is distinct from alternative.category_id then blocked:='incompatible_alternative';
 elsif l.id is null or l.archived or l.paused_at is not null then blocked:='f48LineUnavailable';
 elsif mode='MACHINE'and coalesce(o.actual_line_id,o.line_id)is distinct from original.line_id then blocked:='f48TransferChanged';
 elsif mode='MACHINE'and alternative.order_id is distinct from o.id then blocked:='f48TransferChanged';
 elsif mode='LINE'and(coalesce(o.actual_line_id,o.line_id)is distinct from alternative.line_id or alternative.order_id is distinct from o.id)then blocked:='f48TransferChanged';
 elsif original.status not in('stopped','idle','running')then blocked:='f48RecoveryRequired';
 elsif exists(select 1 from public.downtime_events where factory_id=f and work_center_id=original.id and ended_at is null and id is distinct from stop_id)then blocked:='f48RecoveryChanged';
 elsif original.status='stopped'and not exists(select 1 from public.downtime_events where factory_id=f and work_center_id=original.id and id=stop_id and ended_at is null)then blocked:='f48RecoveryRequired';
 elsif exists(select 1 from public.production_orders where factory_id=f and status='active'and id<>o.id and coalesce(actual_line_id,line_id)=l.id)
  or exists(select 1 from public.work_centers where factory_id=f and id=original.id and order_id is not null and order_id<>o.id)then blocked:='f20DestinationBusy';
 elsif exists(select 1 from public.production_transfers where factory_id=f and ended_at is null and id is distinct from t.id and(original.id in(original_id,alternative_id)or alternative.id in(original_id,alternative_id)or mode='LINE'and order_id=o.id))then blocked:='execution_end_transfer_first';
 elsif not exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=original.id and cap.product_id=o.product_id and cap.rate>0 and cap.rate_unit=o.unit)then blocked:='planningIncompatibleLine';
 elsif private.output_work_held(f,o.id)then blocked:='planningQualityHold';end if;
 if blocked is null then
  select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)into n,typed,rate,fastest,setup
  from public.work_centers machine join public.work_center_capabilities cap on cap.factory_id=machine.factory_id and cap.work_center_id=machine.id and cap.product_id=o.product_id
  where machine.factory_id=f and machine.line_id=l.id and not machine.archived;
  if n=0 or typed<>n or rate<=0 or rate<>fastest then blocked:='planningMissingRate';end if;
 end if;
 if blocked is null then
  if exists(select 1 from public.work_centers machine where machine.factory_id=f and machine.line_id=l.id and not machine.archived and machine.id<>original.id
   and (case when mode='MACHINE'then private.machine_required_for_work(f,machine.id,o.id)else machine.dependency_mode in('blocking','buffer')and machine.impact_scope<>'none' or exists(select 1 from public.production_routing_steps route where route.factory_id=f and route.product_id=o.product_id and route.kind='work_center'and route.work_center_id=machine.id)end)
   and(machine.status not in('idle','running')or exists(select 1 from public.downtime_events d where d.factory_id=f and d.work_center_id=machine.id and d.ended_at is null)))then blocked:='f48DependencyStopped';end if;
 end if;
 if blocked is null then
  finish_at:=private.finish_after_working_minutes(f,statement_timestamp(),greatest(ceil(remaining*60/rate)+coalesce(setup,0),1)::integer);
  if private.maintenance_capacity_conflict(f,l.id,o.product_id,original.id,statement_timestamp(),finish_at,null,o.id,false)is not null then blocked:='maintenance_capacity_reserved';end if;
 end if;
 if blocked is null then
  if private.production_stock_enabled(f)and private.production_stock_eligible(f,o.id)then materials:=private.execution_dispatch_materials_for_line(f,o.id,l.id);
  else materials:=private.material_start_readiness(f,o.id);end if;
  if materials->>'ready'is distinct from 'true'then blocked:='production_material_not_ready';end if;
 end if;
 -- Mutable stock is revalidated under admission locks; it is not trusted from this display.
 fingerprint:=encode(sha256(convert_to(jsonb_build_array(mode,reference,to_jsonb(o),to_jsonb(original),to_jsonb(alternative),to_jsonb(l),
  (select coalesce(jsonb_agg(to_jsonb(d)order by id),'[]')from public.downtime_events d where factory_id=f and work_center_id in(original.id,alternative.id)and ended_at is null),
  (select coalesce(jsonb_agg(to_jsonb(cap)order by work_center_id),'[]')from public.work_center_capabilities cap where factory_id=f and product_id=o.product_id))::text,'UTF8')),'hex');
 return jsonb_build_object('factory',f,'work_center',w,'available',true,'mode',mode,'transfer_id',reference,'item',o.id,'code',o.code,'original',to_jsonb(original),'alternative',to_jsonb(alternative),
  'line',to_jsonb(l),'recovery_required',original.status='stopped','source_stop',stop_id,'ready',blocked is null,'blocker',blocked,'materials',materials,'fingerprint',fingerprint);
end$$;
revoke all on function private.production_return_state(uuid,uuid)from public,anon,authenticated,service_role;

create function public.production_return_context(factory uuid,work_center uuid)returns jsonb language plpgsql stable security definer set search_path=''as $$begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'orders','view');
 if not exists(select 1 from public.work_centers where factory_id=factory and id=work_center)then raise exception 'not_found';end if;
 return private.production_return_state(factory,work_center);end$$;
revoke all on function public.production_return_context(uuid,uuid)from public,anon,service_role;grant execute on function public.production_return_context(uuid,uuid)to authenticated;

create function public.production_return_submit(factory uuid,item uuid,source_machine uuid,alternative_machine uuid,transfer_id uuid,
 reason text,fingerprint text,request_id uuid,output_confirmed boolean)returns jsonb language plpgsql security definer set search_path=''as $$
declare o public.production_orders;prior private.production_execution_commands;intent jsonb;context jsonb;response jsonb;physical jsonb;state text;message text;detail text;mode text;stop_id uuid;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'centers','edit');
 if current_setting('transaction_isolation')<>'read committed'then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 if request_id is null or source_machine is null or alternative_machine is null or transfer_id is null or reason is null or length(reason)>240 or fingerprint is null or fingerprint!~'^[a-f0-9]{64}$'or output_confirmed is null then raise exception 'execution_context_changed'using errcode='22023';end if;
 intent:=jsonb_build_object('item',item,'operation','RETURN_PRODUCTION','source_machine',source_machine,'alternative_machine',alternative_machine,'transfer_id',transfer_id,'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'centers','edit');
 select *into prior from private.production_execution_commands c where c.factory_id=factory and c.request_id=production_return_submit.request_id;
 if found then if prior.actor<>auth.uid()or prior.item_id<>item or prior.intent<>intent or prior.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  if prior.result->>'outcome'='REJECTED'then return prior.result;end if;return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',prior.result);end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;if not found then raise exception 'not_found';end if;
 perform 1 from public.production_lines where factory_id=factory order by id for update;
 perform 1 from public.work_centers where factory_id=factory order by id for update;
 begin
  if char_length(btrim(reason))<3 then raise exception 'execution_reason_required'using errcode='22023';end if;
  if output_confirmed is distinct from true then raise exception 'f48ConfirmHandover'using errcode='22023';end if;
  context:=private.production_return_state(factory,source_machine);
  if context->>'available'is distinct from 'true'or(context->>'item')::uuid<>item or(context->>'transfer_id')::uuid<>transfer_id
   or context#>>'{original,id}'<>source_machine::text or context#>>'{alternative,id}'<>alternative_machine::text or context->>'fingerprint'is distinct from fingerprint then raise exception 'f48TransferChanged'using errcode='40001';end if;
  perform private.refresh_production_stock(factory);context:=private.production_return_state(factory,source_machine);
  if context->>'ready'is distinct from 'true'then raise exception using message=context->>'blocker',errcode='22023',detail=case when context->>'blocker'='production_material_not_ready'then(context->'materials')::text end;end if;
  mode:=context->>'mode';stop_id:=(context->>'source_stop')::uuid;
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state)
  values(factory,request_id,auth.uid(),item,'RETURN_PRODUCTION',btrim(reason),intent,to_jsonb(o)||jsonb_build_object('return_mode',mode,'transfer_id',transfer_id,'source_machine',alternative_machine,'alternative_machine',source_machine,
   'source_line',coalesce(o.actual_line_id,o.line_id),'destination_line',context#>>'{original,line_id}','source_downtime',stop_id,'original_context',context));
  if mode='MACHINE'then
   -- Stop carrying work, not a fabricated equipment failure. Preserve any genuine stop.
   if context#>>'{alternative,status}'='running'then perform private.change_status(factory,alternative_machine,'idle',null,null,reason,null,null,null,false);end if;
   -- Existing audited recovery/finish-transfer/projector/loss triggers own the lifecycle.
   perform private.change_status(factory,source_machine,'running',null,null,reason,null,null,null,false);
   if exists(select 1 from public.production_transfers where factory_id=factory and id=transfer_id and ended_at is null)then raise exception 'f48TransferChanged';end if;
  else
   if exists(select 1 from public.production_transfers where factory_id=factory and order_id=item and ended_at is null)then raise exception 'execution_end_transfer_first';end if;
   if context#>>'{original,status}'='stopped'then perform private.change_status(factory,source_machine,'idle',null,null,reason,null,null,null,false);end if;
   perform public.production_execution_action(factory,item,'INTERRUPT',reason,private.execution_fingerprint(factory,item),gen_random_uuid(),true);
   update public.production_orders set actual_line_id=case when line_id=(context#>>'{original,line_id}')::uuid then null else(context#>>'{original,line_id}')::uuid end where factory_id=factory and id=item;
   perform public.production_execution_action(factory,item,'RESUME',reason,private.execution_fingerprint(factory,item),gen_random_uuid(),false);
  end if;
  physical:=private.execution_machine_readiness(factory,item,(context#>>'{original,line_id}')::uuid,o.product_id);
  if physical->>'ready'is distinct from 'true'then raise exception 'execution_machine_stopped'using errcode='22023';end if;
  physical:=private.maintenance_execution_readiness(factory,item,(context#>>'{original,line_id}')::uuid,o.product_id);
  if physical->>'ready'is distinct from 'true'then raise exception 'maintenance_machine_not_ready'using errcode='22023';end if;
  perform private.refresh_production_stock(factory);
  response:=public.production_execution_context(factory,item)||jsonb_build_object('return_transfer',jsonb_build_object('request_id',request_id,'transfer_id',transfer_id,'source_machine',source_machine,'alternative_machine',alternative_machine,'mode',mode,'actor',auth.uid(),'reason',btrim(reason),'returned_at',clock_timestamp()));
  update private.production_execution_commands c set result=response where c.factory_id=factory and c.request_id=production_return_submit.request_id;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',response);
 exception when others then get stacked diagnostics state=returned_sqlstate,message=message_text,detail=pg_exception_detail;
  response:=jsonb_build_object('outcome','REJECTED','request_id',request_id,'error',jsonb_build_object('code',state,'message',message,'details',case when message='production_material_not_ready'then detail end));
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,result)
  values(factory,request_id,auth.uid(),item,'RETURN_PRODUCTION',btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_rejected',true),response);return response;
 end;
end$$;
revoke all on function public.production_return_submit(uuid,uuid,uuid,uuid,uuid,text,text,uuid,boolean)from public,anon,service_role;
grant execute on function public.production_return_submit(uuid,uuid,uuid,uuid,uuid,text,text,uuid,boolean)to authenticated;
