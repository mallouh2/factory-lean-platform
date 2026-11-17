-- A cut length is a physical stock identity, not a display-only conversion.
alter table public.products add column length_parent_id uuid, add column piece_length_m numeric;
alter table public.products add constraint pipe_parent_factory foreign key(factory_id,length_parent_id) references public.products(factory_id,id),
 add constraint pipe_length_identity check ((length_parent_id is null and piece_length_m is null) or (length_parent_id is not null and length_parent_id<>id and piece_length_m is not null and piece_length_m>0 and piece_length_m<=1000 and piece_length_m=round(piece_length_m,6) and stock_unit='piece' and unit='piece' and stage='finished' and product_kind='FINISHED_PRODUCT'));
create unique index pipe_stock_identity on public.products(factory_id,length_parent_id,piece_length_m) where length_parent_id is not null;
create function private.pipe_stock_guard() returns trigger language plpgsql security definer set search_path='' as $$begin
 if tg_op='UPDATE' and (new.length_parent_id is distinct from old.length_parent_id or new.piece_length_m is distinct from old.piece_length_m) then raise exception 'pipe_identity_immutable';end if;
 if new.length_parent_id is not null and not exists(select 1 from public.products p where p.factory_id=new.factory_id and p.id=new.length_parent_id and p.length_parent_id is null and p.stage='finished' and p.stock_unit='meter' and p.product_kind='FINISHED_PRODUCT') then raise exception 'pipe_product_invalid';end if;
 if tg_op='UPDATE' and exists(select 1 from public.products c where c.length_parent_id=new.id) and (new.stock_unit<>'meter' or new.stage<>'finished' or new.product_kind<>'FINISHED_PRODUCT')then raise exception 'pipe_identity_immutable';end if;
 return new;end$$;
create trigger pipe_stock_identity before insert or update on public.products for each row execute function private.pipe_stock_guard();
create function private.pipe_stock_product(f uuid,base uuid,metres numeric) returns uuid language plpgsql security definer set search_path='' as $$
declare p public.products;result uuid;step public.production_routing_steps;step_id uuid;begin
 perform private.fulfillment_lock(f);
 if metres is null or metres::text in('NaN','Infinity','-Infinity') or metres<=0 or metres>1000 or metres<>round(metres,6)then raise exception 'pipe_length_invalid';end if;
 select * into p from public.products where factory_id=f and id=base for update;
 if not found or p.product_kind<>'FINISHED_PRODUCT' or p.stock_unit<>'meter' or p.length_parent_id is not null or p.unit_weight_kg is null then raise exception 'pipe_product_invalid';end if;
 select id into result from public.products where factory_id=f and length_parent_id=base and piece_length_m=metres;
 if result is not null then return result;end if;
 insert into public.products(factory_id,name,name_ar,code,unit,category,diameter,length,color,weight,standard_rate,stage,supply_mode,stock_unit,supply_source,product_kind,formula_product_id,unit_weight_kg,length_parent_id,piece_length_m)
 values(f,left(p.name,90)||' · '||trim_scale(metres)::text||' m/pipe',case when p.name_ar<>'' then left(p.name_ar,90)||' · '||trim_scale(metres)::text||' م/أنبوب' else '' end,'CUT-'||substr(md5(base::text||':'||trim_scale(metres)::text),1,28),'piece',p.category,p.diameter,metres,p.color,p.weight,case when p.standard_rate is not null then p.standard_rate/metres end,'finished','MAKE_TO_ORDER','piece',p.supply_source,'FINISHED_PRODUCT',p.formula_product_id,p.unit_weight_kg*metres,base,metres) returning id into result;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)select f,work_center_id,result,rate/metres,'piece',setup_minutes from public.work_center_capabilities where factory_id=f and product_id=base and rate_unit='meter';
 insert into private.production_input_routes(factory_id,product_id,scope,routing_step_id,mode,updated_by)select f,result,scope,routing_step_id,mode,auth.uid() from private.production_input_routes where factory_id=f and product_id=base and routing_step_id is null;
 for step in select * from public.production_routing_steps where factory_id=f and product_id=base order by position loop
 insert into public.production_routing_steps(factory_id,product_id,position,kind,line_id,work_center_id,output_product_id)values(f,result,step.position,step.kind,step.line_id,step.work_center_id,case when step.output_product_id=base then result else step.output_product_id end)returning id into step_id;
 insert into private.production_input_routes(factory_id,product_id,scope,routing_step_id,mode,updated_by)select f,result,step_id,step_id,mode,auth.uid() from private.production_input_routes where factory_id=f and product_id=base and routing_step_id=step.id;
 end loop;
 return result;end$$;
revoke all on function private.pipe_stock_guard(),private.pipe_stock_product(uuid,uuid,numeric)from public,anon,authenticated;
CREATE OR REPLACE FUNCTION public.create_sales_order(factory uuid, payload jsonb, request_id uuid DEFAULT gen_random_uuid())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result uuid;entry jsonb;buffer integer;prod uuid;u text;begin
 perform private.require_permission(factory,'sales_orders','create');
 result:=private.fulfillment_retry(factory,request_id,'create',payload);if result is not null then return result;end if;
 if jsonb_typeof(payload)<>'object' or jsonb_typeof(payload->'lines') is distinct from 'array'
 or jsonb_array_length(payload->'lines') not between 1 and 50
 then raise exception 'fulfillment_invalid';end if;
 if payload ? 'promised_delivery' then raise exception 'sales_promise_read_only';end if;
 select delivery_buffer_days into buffer from public.factories where id=factory;
 if payload ? 'safety_buffer_days' and (payload->>'safety_buffer_days')::integer<>buffer then
 perform private.require_permission(factory,'sales_orders','approve');buffer:=(payload->>'safety_buffer_days')::integer;end if;
 insert into public.sales_orders(factory_id,customer_reference,requested_by,created_by,requested_delivery,promised_delivery,safety_buffer_days,notes)
 values(factory,coalesce(payload->>'customer_reference',''),auth.uid(),auth.uid(),nullif(payload->>'requested_delivery','')::timestamptz,
 null,buffer,coalesce(payload->>'notes','')) returning id into result;
 for entry in select value from jsonb_array_elements(payload->'lines') loop
 prod:=(entry->>'product_id')::uuid;u:=entry->>'unit';
 if not exists(select 1 from public.products where factory_id=factory and id=prod and stage='finished' and product_kind='FINISHED_PRODUCT' and stock_unit in('meter','piece'))then raise exception 'fulfillment_product';end if;
 if entry ? 'piece_length_m' and entry->>'piece_length_m' is not null then
 if u<>'piece' or (entry->>'quantity')::numeric<>trunc((entry->>'quantity')::numeric)then raise exception 'pipe_count_invalid';end if;
 prod:=private.pipe_stock_product(factory,prod,(entry->>'piece_length_m')::numeric);
 end if;
 if exists(select 1 from public.products p where p.id=prod and p.stock_unit is distinct from u)then raise exception 'fulfillment_stock_identity';end if;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit,release_when_ready)
 values(factory,result,prod,(entry->>'quantity')::numeric,entry->>'unit',coalesce((entry->>'release_when_ready')::boolean,false));
 end loop;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'create',payload,result,clock_timestamp());return result;
end$function$;
-- Every downstream posting retains the derived product ID and whole-pipe quantities.
create function private.pipe_quantity_guard()returns trigger language plpgsql security definer set search_path='' as $$declare p uuid;v jsonb:=to_jsonb(new);k text;begin
 p:=case when tg_table_name='production_entries' then(select product_id from public.production_orders where factory_id=new.factory_id and id=(v->>'order_id')::uuid)else (v->>'product_id')::uuid end;
 if exists(select 1 from public.products where id=p and factory_id=new.factory_id and length_parent_id is not null)then
 foreach k in array array['target_quantity','produced_quantity','rejected_quantity','remaining_quantity','overproduction_quantity','quality_rejected_quantity','replacement_good_quantity','accepted_good_quantity','fulfillment_good_quantity','accepted_remaining_quantity','quality_measurement_delta','quality_output_good_delta','running_good','input_quantity','quantity','dispatched_quantity','good_quantity','effective_good','unfinished_quantity','effective_unfinished','on_hand','reserved','stock_delta','reserved_delta']loop
 if v->>k is not null and ((v->>k)::numeric::text in('NaN','Infinity','-Infinity') or (v->>k)::numeric<>trunc((v->>k)::numeric))then raise exception 'pipe_count_invalid';end if;end loop;end if;return new;end$$;
do $$declare tab text;begin foreach tab in array array['sales_order_lines','production_orders','production_entries','finished_goods_balances','finished_goods_movements']loop execute format('create trigger pipe_whole_quantity before insert or update on public.%I for each row execute function private.pipe_quantity_guard()',tab);end loop;end$$;
revoke all on function private.pipe_quantity_guard()from public,anon,authenticated;
-- A single authorized batch reader supplies the shared compact reference component.
create function public.order_identity_context(factory uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$begin
 perform private.require_permission(factory,'factory','view');
 if not public.can_access(factory,'sales_orders','view')then return jsonb_build_object('rows','[]'::jsonb);end if;
 if not(public.can_access(factory,'orders','view')or public.can_access(factory,'warehouse','view')or public.can_access(factory,'quality','view')or public.can_access(factory,'sales_orders','view'))then raise exception 'permission_denied';end if;
 return jsonb_build_object('rows',coalesce((select jsonb_agg(x)from(
 select s.id::text id,s.code,s.customer_reference customer,s.notes description,null::text sales_code from public.sales_orders s where s.factory_id=factory
 union all select o.id::text,o.code,s.customer_reference,s.notes,s.code from public.production_orders o left join public.production_requests r on r.factory_id=o.factory_id and r.id=o.request_id left join public.sales_order_lines l on l.factory_id=r.factory_id and l.id=r.sales_order_line_id left join public.sales_orders s on s.factory_id=l.factory_id and s.id=l.order_id where o.factory_id=factory
 union all select r.id::text,r.code,s.customer_reference,s.notes,s.code from public.production_requests r left join public.sales_order_lines l on l.factory_id=r.factory_id and l.id=r.sales_order_line_id left join public.sales_orders s on s.factory_id=l.factory_id and s.id=l.order_id where r.factory_id=factory
 )x),'[]'::jsonb));end$$;
revoke all on function public.order_identity_context(uuid)from public,anon;
grant execute on function public.order_identity_context(uuid)to authenticated;

CREATE OR REPLACE FUNCTION private.sales_order_detail(f uuid, sales uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare so public.sales_orders;sl record;allocation record;lines jsonb:='[]';line_estimate timestamptz;line_earliest timestamptz;
 earliest timestamptz:=now();estimated timestamptz;plan jsonb;early_plan jsonb;virtual jsonb:='[]';early_virtual jsonb:='[]';
 unknown boolean:=false;line_unknown boolean;early_unknown boolean:=false;target timestamptz;all_ready boolean:=true;complete boolean;ready boolean;
 reserved_qty numeric;incoming_qty numeric;needed numeric;state text;risk text;begin
 select * into so from public.sales_orders where factory_id=f and id=sales;if not found then return null;end if;
 select ((so.requested_delivery at time zone fac.timezone)-make_interval(days=>so.safety_buffer_days)) at time zone fac.timezone into target from public.factories fac where fac.id=f;
 for sl in select l.*,p.name product_name,p.name_ar product_name_ar,p.supply_source,p.piece_length_m::text,(l.quantity*p.piece_length_m)::text total_length_m from public.sales_order_lines l join public.products p on p.id=l.product_id where l.factory_id=f and l.order_id=sales order by l.id loop
 select coalesce(sum(r.quantity),0) into reserved_qty from public.finished_goods_reservations r where r.factory_id=f and r.line_id=sl.id;
 select coalesce(sum(ia.quantity),0) into incoming_qty from public.sales_incoming_allocations ia where ia.factory_id=f and ia.line_id=sl.id;
 needed:=greatest(sl.quantity-sl.dispatched_quantity-reserved_qty,0);complete:=sl.dispatched_quantity=sl.quantity;
 ready:=complete or reserved_qty>=sl.quantity-sl.dispatched_quantity;all_ready:=all_ready and ready;
 if so.status='draft' then needed:=greatest(needed-coalesce((select b.on_hand-b.reserved from public.finished_goods_balances b where b.factory_id=f and b.product_id=sl.product_id and b.unit=sl.unit),0),0);end if;
 line_unknown:=false;
 line_estimate:=coalesce((select max(created_at) from public.finished_goods_movements where factory_id=f and sales_line_id=sl.id and (reserved_delta>0 or kind='dispatch')),so.approved_at,so.created_at);line_earliest:=now();
 for allocation in select o.*,ia.quantity allocated from public.sales_incoming_allocations ia join public.production_orders o on o.id=ia.item_id
 where ia.factory_id=f and ia.line_id=sl.id and ia.quantity>0 order by o.id loop
 if allocation.status not in ('planned','active') then line_unknown:=true;early_unknown:=true;continue;end if;
 if allocation.status='active' then
 -- An overdue active job cannot be moved to another line by a forecast. Mark unknown rather than invent execution.
 if allocation.line_id is null or allocation.expected_finish is null or allocation.expected_finish+greatest(coalesce(allocation.actual_start-allocation.start_time,interval '0'),interval '0')<=now() then line_unknown:=true;early_unknown:=true;
 else line_estimate:=greatest(line_estimate,allocation.expected_finish+greatest(coalesce(allocation.actual_start-allocation.start_time,interval '0'),interval '0'));line_earliest:=greatest(line_earliest,line_estimate);end if;
 continue;end if;
 early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,private.quality_production_remaining(f,allocation.id),allocation.id,extra=>early_virtual);
 if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 if allocation.expected_finish is not null and allocation.line_id is not null and allocation.expected_finish>now() then
 line_estimate:=greatest(line_estimate,allocation.expected_finish);
 else line_unknown:=true;
 end if;end loop;
 if needed>incoming_qty then
 line_unknown:=true;
 if sl.supply_source='MANUFACTURED' then
  early_plan:=private.fulfillment_slot(f,sl.product_id,sl.unit,needed-incoming_qty,extra=>early_virtual);
  if early_plan is null then early_unknown:=true;else early_virtual:=early_virtual||jsonb_build_array(early_plan);line_earliest:=greatest(line_earliest,(early_plan->>'finish')::timestamptz);end if;
 else early_unknown:=true;end if;
 end if;
 unknown:=unknown or line_unknown;
 earliest:=greatest(earliest,line_earliest);estimated:=greatest(estimated,line_estimate);
 lines:=lines||jsonb_build_array(to_jsonb(sl)||jsonb_build_object('reserved_quantity',reserved_qty,'incoming_quantity',incoming_qty,'production_required',case when sl.supply_source='MANUFACTURED' then needed else incoming_qty end,'external_shortage',case when sl.supply_source='EXTERNAL' then greatest(needed-incoming_qty,0) else 0 end,'source_decision_quantity',case when sl.supply_source='BOTH' then greatest(needed-incoming_qty,0) else 0 end,'ready',ready,
 'estimated_ready',case when not line_unknown then line_estimate end,'dispatch_allowed',not complete and ready and sl.release_when_ready));
 end loop;
 state:=case when so.status in ('draft','completed','cancelled') then so.status when all_ready then 'ready'
 when exists(select 1 from public.sales_order_lines l where l.order_id=sales and l.dispatched_quantity>0) then 'partially_dispatched' else 'approved' end;
 risk:=case when so.requested_delivery is null then 'none' when so.status in ('draft','cancelled','completed') then 'none'
 when (so.requested_delivery<now() and not all_ready) or (not unknown and estimated>so.requested_delivery) then 'late'
 when unknown then 'unknown' when estimated>target then 'at_risk' else 'on_time' end;
 if all_ready then lines:=(select coalesce(jsonb_agg(x||jsonb_build_object('dispatch_allowed',(x->>'dispatched_quantity')::numeric<(x->>'quantity')::numeric)),'[]') from jsonb_array_elements(lines) x);end if;
 return to_jsonb(so)||jsonb_build_object('lines',lines,'fulfillment_status',state,'risk',risk,'target_ready',target,
 'earliest_feasible',case when not early_unknown then earliest end,'estimated_ready',case when not unknown then estimated end,
 'requested_feasible',case when so.requested_delivery is not null and not early_unknown then earliest<=so.requested_delivery end,
 'delay_days',case when so.requested_delivery is not null and not unknown then greatest(ceil(extract(epoch from (estimated-so.requested_delivery))/86400),0) end,
 'dispatch_allowed',so.status='approved' and all_ready);
end$function$;

-- Cut-length rates follow the parent meter rate when an authorized configuration changes.
CREATE OR REPLACE FUNCTION private.configure_center_capabilities(f uuid, w uuid, capabilities jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform private.require_permission(f,'centers','edit');perform private.maintenance_planning_lock(f);
 perform private.require_permission(f,'centers','edit');if exists(select 1 from jsonb_array_elements(capabilities)c join public.products p on p.id=(c->>'product_id')::uuid where p.factory_id=f and p.length_parent_id is not null)then raise exception 'pipe_capability_inherited';end if;
 perform private.maintenance_capabilities_base(f,w,capabilities);
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)
 select f,w,p.id,c.rate/p.piece_length_m,'piece',c.setup_minutes from public.products p join public.work_center_capabilities c on c.factory_id=p.factory_id and c.product_id=p.length_parent_id and c.work_center_id=w and c.rate_unit='meter' where p.factory_id=f and p.length_parent_id is not null;
end$function$;
