-- Never close genuine alternative downtime as a side effect of idling a healthy spare.
CREATE OR REPLACE FUNCTION private.production_return_state(f uuid, w uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
 elsif mode='MACHINE'and alternative.status='running'and exists(select 1 from public.downtime_events d where d.factory_id=f and d.work_center_id=alternative.id and d.ended_at is null)then blocked:='f48AlternativeStopConflict';
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
end$function$;
