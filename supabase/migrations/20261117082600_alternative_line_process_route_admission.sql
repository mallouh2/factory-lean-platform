-- F20: preserve the approved process/BOM while resolving its actual machine.
-- Tested in rollback-only QA rehearsals; no existing routing or accounting rows changed.
-- Resolve explicit logical process equipment through audited actual handovers.
-- The approved product routing and BOM are never edited by this mapping.
create function private.execution_effective_center(f uuid,i uuid,w uuid)returns uuid language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;c record;effective uuid:=w;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 if o.actual_line_id is null then return w;end if;
 for c in select intent from private.production_execution_commands where factory_id=f and item_id=i and operation='TRANSFER_LINE'
 and result->>'outcome'is distinct from 'REJECTED'order by started_at,request_id loop
  if (c.intent->>'source_machine')::uuid=effective then effective:=(c.intent->>'alternative_machine')::uuid;end if;
 end loop;return effective;end$$;
revoke all on function private.execution_effective_center(uuid,uuid,uuid)from public,anon,authenticated,service_role;
create index execution_transfer_history_item on private.production_execution_commands(factory_id,item_id,operation,started_at);
CREATE OR REPLACE FUNCTION private.material_requirement_inputs(f uuid, i uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$declare o public.production_orders;p public.products;r private.production_input_routes;b public.bom_versions;compound uuid;mass numeric;v jsonb;matches integer;begin
 select *into o from public.production_orders where factory_id=f and id=i;select *into p from public.products where factory_id=f and id=o.product_id;
 if o.id is null then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 -- Existing completion/rework owns its source-lot requirement; never explode a recipe again.
 if exists(select 1 from private.manufactured_completion_work where factory_id=f and item_id=i)or o.quality_origin_rejection_id is not null then return jsonb_build_object('existing_source_work',true,'inputs','[]'::jsonb);end if;
 select count(*)into matches from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=o.line_id;
 if matches>1 then return jsonb_build_object('warning','material_route_ambiguous');end if;
 if matches=1 then select x.*into r from private.production_input_routes x join public.production_routing_steps s on s.id=x.routing_step_id join public.work_centers w on w.id=s.work_center_id where x.factory_id=f and x.product_id=p.id and w.line_id=o.line_id;else select *into r from private.production_input_routes where factory_id=f and product_id=p.id and scope='00000000-0000-0000-0000-000000000000';end if;
 if r.product_id is null then return jsonb_build_object('warning','material_route_missing');end if;
 if o.unit is distinct from p.stock_unit then return jsonb_build_object('warning','material_unit_missing');end if;
 mass:=case when r.mode='COMPOUND_MANUFACTURE'and p.stock_unit='kg'then o.target_quantity else o.target_quantity*p.unit_weight_kg end;
 if mass is null or mass<=0 or mass::text in('NaN','Infinity','-Infinity')then return jsonb_build_object('warning','material_weight_missing');end if;
 compound:=case when r.mode='COMPOUND_MANUFACTURE'then p.id else p.formula_product_id end;
 if r.mode='COMPOUND_STOCK'then
 if not exists(select 1 from public.products where factory_id=f and id=compound and product_kind='MANUFACTURED_INTERMEDIATE'and stock_unit='kg')then return jsonb_build_object('warning','material_configuration_invalid');end if;
 v:=jsonb_build_array(jsonb_build_object('kind','product','id',compound,'unit','kg','quantity',trim_scale(mass)::text));
 else
 select *into b from public.bom_versions where factory_id=f and product_id=compound and output_unit='kg'order by version desc,created_at desc,id desc limit 1;
 if b.id is null or not exists(select 1 from public.bom_items where factory_id=f and bom_id=b.id)then return jsonb_build_object('warning','material_recipe_missing');end if;
 if exists(select 1 from public.bom_items x join public.materials m on m.id=x.material_id where x.factory_id=f and x.bom_id=b.id and(x.unit<>m.unit or m.inventory_kind<>'RAW_MATERIAL'))then return jsonb_build_object('warning','material_unit_missing');end if;
 select jsonb_agg(jsonb_build_object('kind','material','id',material_id,'unit',unit,'quantity',trim_scale(quantity)::text)order by material_id)into v from(select x.material_id,x.unit,sum(mass*x.quantity/b.batch_quantity*(1+x.waste_allowance))quantity from public.bom_items x where x.factory_id=f and x.bom_id=b.id group by x.material_id,x.unit)q;
 end if;
 return jsonb_build_object('mode',r.mode,'route',r.scope,'route_revision',r.revision,'recipe',b.id,'recipe_version',b.version,'inputs',v);
end$function$
;
create or replace function private.material_requirement_inputs_for_line(f uuid,i uuid,destination uuid)returns jsonb language sql stable set search_path=''as $$select private.material_requirement_inputs(f,i)$$;
CREATE OR REPLACE FUNCTION private.execution_machine_readiness(f uuid, i uuid, l uuid, p uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.work_centers;e public.work_centers;t public.production_transfers;begin
 for c in select *from public.work_centers where factory_id=f and not archived and(line_id=l
 or id in(select private.execution_effective_center(f,i,work_center_id) from public.production_routing_steps where factory_id=f and product_id=p and kind='work_center'))order by id loop
 if not private.machine_required_for_work(f,c.id,i)then continue;end if;
 e:=c;
 select *into t from public.production_transfers where factory_id=f and original_id=c.id and ended_at is null;
 if t.id is not null and t.order_id=i then select *into e from public.work_centers where factory_id=f and id=t.alternative_id and category_id=c.category_id and not archived;end if;
 if e.id is null or e.status not in('running','idle')or exists(select 1 from public.downtime_events d where d.factory_id=f and d.work_center_id=e.id and d.ended_at is null)
 or exists(select 1 from public.production_transfers x where x.factory_id=f and x.alternative_id=e.id and x.ended_at is null and x.order_id<>i)then
 return jsonb_build_object('ready',false,'applicable',true,'reason','MACHINE_STOPPED','machine',to_jsonb(e));end if;
 end loop;return jsonb_build_object('ready',true,'applicable',true,'reason',null,'machine',null);end$function$
;
CREATE OR REPLACE FUNCTION private.maintenance_execution_readiness(f uuid, i uuid, l uuid, p uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare serviced public.work_centers;effective public.work_centers;incoming public.production_transfers;
 outgoing public.production_transfers;own_required boolean;borrow_required boolean;first_machine jsonb;machine jsonb;why text;begin
 for serviced in select distinct c.* from public.maintenance_schedules s
 join public.maintenance_schedule_resources r on r.factory_id=s.factory_id and r.schedule_id=s.id and r.resource_kind='MACHINE'
 join public.work_centers c on c.factory_id=r.factory_id and c.id=r.machine_id
 where s.factory_id=f and s.state='RELEASED' order by c.id loop
 own_required:=exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p
 and rs.kind='work_center' and private.execution_effective_center(f,i,rs.work_center_id)=serviced.id) or
 (not serviced.archived and serviced.line_id=l and serviced.dependency_mode in ('blocking','buffer') and serviced.impact_scope<>'none');
 select * into incoming from public.production_transfers t where t.factory_id=f and t.alternative_id=serviced.id and t.ended_at is null;
 borrow_required:=incoming.id is not null and exists(select 1 from public.work_centers original where original.factory_id=f
 and original.id=incoming.original_id and not original.archived and
 ((original.line_id=l and original.dependency_mode in ('blocking','buffer') and original.impact_scope<>'none')
 or exists(select 1 from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center' and private.execution_effective_center(f,i,rs.work_center_id)=original.id)));
 if not coalesce(own_required,false) and not coalesce(borrow_required,false) then continue;end if;
 effective:=serviced;why:=null;
 -- The existing current association uses highest event revision, not timestamps.
 if exists(select 1 from public.maintenance_stop_associations a join public.maintenance_schedules s
 on s.factory_id=a.factory_id and s.id=a.schedule_id join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id
 where a.factory_id=f and s.state='RELEASED' and d.work_center_id=serviced.id and d.ended_at is null and a.operation='LINK'
 and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)) then
 why:='OPEN_LINKED_STOP';
 elsif incoming.id is not null and private.execution_center_order(f,serviced.id,serviced.line_id,serviced.order_id) is distinct from i then why:='TRANSFER_OWNERSHIP';
 elsif own_required then
 select * into outgoing from public.production_transfers t where t.factory_id=f and t.original_id=serviced.id and t.ended_at is null;
 if outgoing.id is not null then
 if outgoing.order_id is distinct from i then why:='TRANSFER_OWNERSHIP';else
 select * into effective from public.work_centers c where c.factory_id=f and c.id=outgoing.alternative_id;
 if effective.id is null or effective.category_id is distinct from serviced.category_id then why:='MACHINE_UNAVAILABLE';end if;
 end if;end if;
 end if;
 if why is null then
 if effective.archived then why:='MACHINE_UNAVAILABLE';
 elsif effective.status not in ('idle','running') or effective.status is null then why:='PHYSICAL_STATUS';end if;
 end if;
 machine:=jsonb_build_object('id',coalesce(effective.id,serviced.id),'code',coalesce(effective.code,serviced.code),
 'name',coalesce(effective.name,serviced.name),'name_ar',coalesce(effective.name_ar,serviced.name_ar),'status',effective.status);
 first_machine:=coalesce(first_machine,machine);
 if why is not null then return jsonb_build_object('applicable',true,'ready',false,'reason',why,'machine',machine);end if;
 end loop;
 return jsonb_build_object('applicable',first_machine is not null,'ready',true,'reason',null,'machine',first_machine);
end$function$
;
CREATE OR REPLACE FUNCTION private.maintenance_occupancy(f uuid, l uuid, p uuid, w uuid, skip_schedule uuid, skip_item uuid, with_production boolean, evaluated timestamp with time zone, range_start timestamp with time zone DEFAULT '-infinity'::timestamp with time zone, range_end timestamp with time zone DEFAULT 'infinity'::timestamp with time zone, record_limit integer DEFAULT NULL::integer)
 RETURNS TABLE(kind text, id uuid, starts timestamp with time zone, ends timestamp with time zone, state text, unknown boolean, sort_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 with scoped as (
 select 'MAINTENANCE'::text kind,s.id,least(s.planned_start,coalesce(s.hold_started_at,s.planned_start),coalesce((select min(d.started_at) from public.maintenance_stop_associations a join public.downtime_events d on d.factory_id=a.factory_id and d.id=a.event_id where a.factory_id=f and a.schedule_id=s.id and a.operation='LINK' and d.ended_at is null and not exists(select 1 from public.maintenance_stop_associations n where n.factory_id=f and n.event_id=a.event_id and n.revision>a.revision)),s.planned_start)) starts,
 case when private.maintenance_active_stop(f,s.id) or s.hold_started_at is not null or s.state='INVALIDATED' or s.planned_end<=evaluated then 'infinity'::timestamptz else s.planned_end end ends,
 s.state,false unknown,s.planned_start sort_at from public.maintenance_schedules s
 where s.factory_id=f and s.id is distinct from skip_schedule and s.state in ('CONFIRMED','INVALIDATED')
 and exists(select 1 from public.maintenance_schedule_resources r left join public.work_centers m on m.factory_id=r.factory_id and m.id=r.machine_id
 where r.factory_id=f and r.schedule_id=s.id and
 ((l is not null and (r.line_id=l or m.line_id=l)) or (w is not null and r.machine_id=w)
 or (p is not null and r.machine_id in(select private.execution_effective_center(f,skip_item,rs.work_center_id) from public.production_routing_steps rs where rs.factory_id=f and rs.product_id=p and rs.kind='work_center'))
 or (l is not null and r.machine_id in(select t.alternative_id from public.production_transfers t join public.production_orders o on o.factory_id=t.factory_id and o.id=t.order_id where t.factory_id=f and t.ended_at is null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l))))
 union all
 select 'PRODUCTION',o.id,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then '-infinity'::timestamptz else o.start_time end,
 case when o.status='active' or o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time then 'infinity'::timestamptz else o.expected_finish end,
 o.status,(o.start_time is null or o.expected_finish is null or o.expected_finish<=o.start_time),o.start_time
 from public.production_orders o where with_production and o.factory_id=f and o.id is distinct from skip_item and o.status in ('planned','active')
 and ((l is not null and (case when o.status='active'then coalesce(o.actual_line_id,o.line_id)else o.line_id end)=l) or (w is not null and
 (o.id in(select c.order_id from public.work_centers c where c.factory_id=f and c.id=w)
 or o.product_id in(select rs.product_id from public.production_routing_steps rs where rs.factory_id=f and rs.work_center_id=w and rs.kind='work_center')))))
 select * from scoped where starts<range_end and ends>range_start order by kind,id limit record_limit;
$function$
;
CREATE OR REPLACE FUNCTION private.machine_required_for_work(f uuid, w uuid, i uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select(c.dependency_mode in('blocking','buffer')and c.impact_scope<>'none')
 or exists(select 1 from public.production_orders o join public.production_routing_steps rs
 on rs.factory_id=o.factory_id and rs.product_id=o.product_id and rs.kind='work_center'
 where o.factory_id=f and o.id=i and private.execution_effective_center(f,i,rs.work_center_id)=c.id)
 from public.work_centers c where c.factory_id=f and c.id=w),false)
$function$
;
CREATE OR REPLACE FUNCTION private.maintenance_production_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare finish_time timestamptz;minutes_required integer;m public.work_centers;begin
 perform private.maintenance_planning_lock(new.factory_id);
 -- Stopping actual work does not create/revise Planning occupancy. Never block
 -- safe release because the preserved historical plan now conflicts with a hold.
 if tg_op='UPDATE'and old.status='active'and new.status='planned'
 and private.execution_command_allowed(new.factory_id,new.id,array['INTERRUPT'])
 and row(old.line_id,old.start_time,old.expected_finish)is not distinct from row(new.line_id,new.start_time,new.expected_finish)then return new;end if;
 if (new.status='planned'or new.actual_line_id is null)and new.status in('planned','active')and new.line_id is not null then
 perform private.maintenance_assert_capacity(new.factory_id,coalesce(new.actual_line_id,new.line_id),new.product_id,null,new.start_time,new.expected_finish,null,new.id,false);
 end if;
 if tg_op='UPDATE' and old.status<>'active' and new.status='active' then
 if private.maintenance_capacity_conflict(new.factory_id,coalesce(new.actual_line_id,new.line_id),new.product_id,null,coalesce(new.execution_started_at,new.actual_start),'infinity',null,new.id,false) is not null then
 select ceil((case when new.execution_started_at is not null then private.ordinary_output_remaining(new.factory_id,new.id)else new.target_quantity end)/min(cap.rate)*60)+max(cap.setup_minutes) into minutes_required
 from public.work_centers c join public.work_center_capabilities cap on cap.factory_id=c.factory_id and cap.work_center_id=c.id
 where c.factory_id=new.factory_id and c.line_id=coalesce(new.actual_line_id,new.line_id) and not c.archived and cap.product_id=new.product_id and cap.rate_unit=new.unit and cap.rate>0;
 -- Conservative intended window, never a claimed actual completion timestamp.
 if minutes_required is null then raise exception 'maintenance_execution_window_unknown';end if;
 finish_time:=private.finish_after_working_minutes(new.factory_id,coalesce(new.execution_started_at,new.actual_start),minutes_required);
 perform private.maintenance_assert_capacity(new.factory_id,coalesce(new.actual_line_id,new.line_id),new.product_id,null,coalesce(new.execution_started_at,new.actual_start),finish_time,null,new.id,false);
 end if;
 end if;
 return new;
end$function$
;
create or replace function private.line_transfer_readiness(f uuid,i uuid,w uuid,a uuid)returns jsonb
language plpgsql stable security definer set search_path=''as $$
declare o public.production_orders;src public.work_centers;dst public.work_centers;line public.production_lines;
 result jsonb;materials jsonb;req jsonb;physical jsonb;capacity jsonb;remaining numeric;line_rate numeric;fastest numeric;n integer;typed integer;setup integer;finish_at timestamptz;blocked text;begin
 select *into o from public.production_orders where factory_id=f and id=i;
 select *into src from public.work_centers where factory_id=f and id=w;
 select *into dst from public.work_centers where factory_id=f and id=a;
 select *into line from public.production_lines where factory_id=f and id=dst.line_id;
 if o.id is null or src.id is null or dst.id is null then raise exception 'not_found';end if;
 remaining:=private.ordinary_output_remaining(f,i);
 if o.status not in('planned','active')or o.actual_finish is not null or remaining<=0 then blocked:='execution_no_remaining';
 elsif o.line_id is null or o.start_time is null or o.expected_finish<=o.start_time then blocked:='execution_plan_required';
 elsif src.archived or src.line_id is distinct from coalesce(o.actual_line_id,o.line_id)then blocked:='f20SourceChanged';
 elsif src.status<>'stopped'or not exists(select 1 from public.downtime_events where factory_id=f and work_center_id=w and ended_at is null)then blocked:='transferStopRequired';
 elsif not exists(select 1 from public.work_center_alternatives where factory_id=f and work_center_id=w and alternative_id=a)
  or src.category_id is distinct from dst.category_id then blocked:='incompatible_alternative';
 elsif dst.archived or line.id is null or line.archived or dst.line_id=src.line_id then blocked:='f20DestinationLineRequired';
 elsif dst.status<>'idle'then blocked:='f20DestinationUnavailable';
 elsif dst.order_id is not null then blocked:='f20DestinationBusy';
 elsif line.paused_at is not null then blocked:='f20DestinationPaused';
 elsif exists(select 1 from public.production_orders where factory_id=f and status='active'and id<>i and coalesce(actual_line_id,line_id)=dst.line_id)
  or exists(select 1 from public.work_centers c where c.factory_id=f and c.line_id=dst.line_id and not c.archived and(c.status='running'or c.order_id is not null and c.order_id<>i))then blocked:='f20DestinationBusy';
 elsif exists(select 1 from public.production_transfers where factory_id=f and ended_at is null and(order_id=i or a in(original_id,alternative_id)or w in(original_id,alternative_id)))then blocked:='execution_end_transfer_first';
 elsif not exists(select 1 from public.work_center_capabilities where factory_id=f and work_center_id=a and product_id=o.product_id and rate>0 and rate_unit=o.unit)then blocked:='planningIncompatibleLine';
 elsif exists(select 1 from public.production_routing_steps r join public.work_centers c on c.factory_id=r.factory_id and c.id=r.work_center_id
  where r.factory_id=f and r.product_id=o.product_id and r.kind='work_center'and c.line_id is distinct from dst.line_id and private.execution_effective_center(f,i,c.id)<>w)then blocked:='f20FixedRoute';
 elsif private.machine_required_for_work(f,w,i)and not(dst.dependency_mode in('blocking','buffer')and dst.impact_scope<>'none')then blocked:='f20DependencyMismatch';
 elsif private.output_work_held(f,i)then blocked:='planningQualityHold';
 elsif not private.production_stock_enabled(f)then blocked:='f20SharedStockRequired';
 elsif not private.production_stock_eligible(f,i)then
  blocked:='production_material_not_ready';materials:=private.material_start_readiness(f,i);
 end if;
 if blocked is null then
  req:=private.material_requirement_inputs_for_line(f,i,dst.line_id);
  if req->>'existing_source_work'='true'or req->>'mode'='COMPOUND_STOCK'then blocked:='f20SourceWorkRequired';
  elsif req->>'warning'is not null then blocked:=req->>'warning';end if;
 end if;
 if blocked is null then
  select count(*),count(*)filter(where cap.rate_unit=o.unit),min(cap.rate),max(cap.rate),max(cap.setup_minutes)
  into n,typed,line_rate,fastest,setup from public.work_centers c join public.work_center_capabilities cap
  on cap.factory_id=c.factory_id and cap.work_center_id=c.id and cap.product_id=o.product_id
  where c.factory_id=f and c.line_id=dst.line_id and not c.archived;
  if n=0 or typed<>n or line_rate<=0 or line_rate<>fastest then blocked:='planningMissingRate';end if;
 end if;
 if blocked is null then
  physical:=private.execution_machine_readiness(f,i,dst.line_id,null);
  if physical->>'ready'is distinct from 'true'then blocked:='execution_machine_stopped';
  else physical:=private.maintenance_execution_readiness(f,i,dst.line_id,null);
   if physical->>'ready'is distinct from 'true'then blocked:='productionReadiness_'||(physical->>'reason');end if;
  end if;
 end if;
 if blocked is null then
  finish_at:=private.finish_after_working_minutes(f,statement_timestamp(),greatest(ceil(remaining*60/line_rate)+coalesce(setup,0),1)::integer);
  capacity:=private.maintenance_capacity_conflict(f,dst.line_id,null,a,statement_timestamp(),finish_at,null,i,false);
  if capacity is not null then blocked:='maintenance_capacity_reserved';end if;
 end if;
 if blocked is null then
  materials:=private.execution_dispatch_materials_for_line(f,i,dst.line_id);
  if materials->>'ready'is distinct from 'true'then blocked:='production_material_not_ready';end if;
 end if;
 return jsonb_build_object('machine',dst.id,'name',dst.name,'name_ar',dst.name_ar,'status',dst.status,
  'line',line.id,'line_name',line.name,'line_name_ar',line.name_ar,'compatible',src.category_id=dst.category_id and exists(
   select 1 from public.work_center_capabilities where factory_id=f and work_center_id=a and product_id=o.product_id and rate>0 and rate_unit=o.unit),
  'ready',blocked is null,'blocker',blocked,'materials',materials,'physical',physical,'maintenance',capacity,'remaining',trim_scale(remaining)::text);
end$$;

create or replace function public.production_line_transfer_submit(factory uuid,item uuid,source_machine uuid,alternative_machine uuid,
 reason text,fingerprint text,request_id uuid,output_confirmed boolean default false)returns jsonb
language plpgsql security definer set search_path=''as $$
declare o public.production_orders;c private.production_execution_commands;intent jsonb;response jsonb;readiness jsonb;
 state text;message text;detail text;source_line uuid;destination_line uuid;stop_id uuid;source_run uuid;child_request uuid;begin
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'centers','edit');
 if current_setting('transaction_isolation')not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 if request_id is null or source_machine is null or alternative_machine is null or reason is null or length(reason)>240 or fingerprint is null or fingerprint!~'^[a-f0-9]{64}$'or output_confirmed is null then raise exception 'execution_context_changed'using errcode='22023';end if;
 intent:=jsonb_build_object('item',item,'operation','TRANSFER_LINE','source_machine',source_machine,'alternative_machine',alternative_machine,
  'reason',btrim(reason),'fingerprint',fingerprint,'output_confirmed',output_confirmed);
 -- The same factory/maintenance/structure lock order as normal execution.
 -- Admission locks survive a rejected subtransaction and protect retry finality.
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform private.maintenance_planning_lock(factory);
 perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 perform private.require_permission(factory,'orders','view');perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'centers','edit');
 select *into c from private.production_execution_commands where factory_id=factory and production_execution_commands.request_id=production_line_transfer_submit.request_id;
 if found then
  if c.actor<>auth.uid()or c.item_id<>item or c.intent<>intent or c.result is null then raise exception 'execution_command_conflict'using errcode='22023';end if;
  if c.result->>'outcome'='REJECTED'then return c.result;end if;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',c.result);
 end if;
 select *into o from public.production_orders where factory_id=factory and id=item for update;if not found then raise exception 'not_found';end if;
 perform 1 from public.work_centers where factory_id=factory and id in(source_machine,alternative_machine)order by id for update;
 begin
  if char_length(btrim(reason))<3 then raise exception 'execution_reason_required'using errcode='22023';end if;
  if private.execution_fingerprint(factory,item)is distinct from fingerprint then raise exception 'execution_context_changed'using errcode='40001';end if;
  if o.status='active'and output_confirmed is distinct from true then raise exception 'execution_record_output_first'using errcode='22023';end if;
  perform private.refresh_production_stock(factory);
  readiness:=private.line_transfer_readiness(factory,item,source_machine,alternative_machine);
  if readiness->>'ready'is distinct from 'true'then
   raise exception using message=readiness->>'blocker',errcode='22023',detail=case when readiness->>'blocker'='production_material_not_ready'then(readiness->'materials')::text else readiness::text end;
  end if;
  source_line:=coalesce(o.actual_line_id,o.line_id);destination_line:=(readiness->>'line')::uuid;
  select id into stop_id from public.downtime_events where factory_id=factory and work_center_id=source_machine and ended_at is null;
  select id into source_run from private.production_execution_runs where factory_id=factory and item_id=item and ended_at is null;
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state)
  values(factory,request_id,auth.uid(),item,'TRANSFER_LINE',btrim(reason),intent,to_jsonb(o)||jsonb_build_object(
   'source_line',source_line,'destination_line',destination_line,'source_machine',source_machine,'alternative_machine',alternative_machine,'source_downtime',stop_id,'source_run',source_run));
  if o.status='active'then
   child_request:=gen_random_uuid();
   perform public.production_execution_action(factory,item,'INTERRUPT',reason,fingerprint,child_request,true);
  end if;
  -- This column never edits line_id, the approved interval or plan revisions.
  update public.production_orders set actual_line_id=destination_line where factory_id=factory and id=item;
  child_request:=gen_random_uuid();
  perform public.production_execution_action(factory,item,case when o.actual_start is null then 'START_SELECTED'else 'RESUME'end,
   reason,private.execution_fingerprint(factory,item),child_request,false);
  response:=public.production_execution_context(factory,item);
  update private.production_execution_commands set result=response where factory_id=factory and production_execution_commands.request_id=production_line_transfer_submit.request_id;
  return jsonb_build_object('outcome','COMMITTED','request_id',request_id,'data',response);
 exception when others then
  get stacked diagnostics state=returned_sqlstate,message=message_text,detail=pg_exception_detail;
  response:=jsonb_build_object('outcome','REJECTED','request_id',request_id,'error',jsonb_build_object('code',state,'message',message,'details',case when message='production_material_not_ready'then detail end));
  insert into private.production_execution_commands(factory_id,request_id,actor,item_id,operation,reason,intent,before_state,result)
  values(factory,request_id,auth.uid(),item,'TRANSFER_LINE',btrim(reason),intent,to_jsonb(o)||jsonb_build_object('execution_rejected',true),response);
  return response;
 end;
end$$;
