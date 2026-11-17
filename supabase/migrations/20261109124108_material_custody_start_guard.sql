-- Group 1: keep reservation, physical handover and measured use distinct.
create function private.material_action_context(f uuid,r uuid)returns jsonb language plpgsql stable set search_path='' as $$
declare m public.material_requests;o public.production_orders;p private.material_request_progress;held numeric;available numeric;reserved numeric;pending numeric;issue numeric;reason text;state text;lead_seconds numeric;due boolean;recheck boolean:=false;begin
 select *into m from public.material_requests where factory_id=f and id=r;
 if not found then raise exception 'material_invalid'using errcode='22023';end if;
 select *into o from public.production_orders where factory_id=f and id=m.production_item_id;
 select *into p from private.material_request_progress where factory_id=f and request_id=r;
 held:=greatest(coalesce(p.issued,0)-coalesce(p.consumed,0),0);reserved:=coalesce(p.reserved,0);pending:=greatest(m.quantity-coalesce(p.issued,0)-reserved,0);
 if m.material_id is not null then
 select coalesce(sum(quantity),0)into available from public.inventory_transactions where factory_id=f and material_id=m.material_id;
 issue:=least(reserved,available);
 if reserved>0 and not exists(select 1 from public.inventory_reservations z where z.id=p.reservation_id and z.factory_id=f and z.material_id=m.material_id and z.order_id=m.production_item_id and z.released_at is null and z.quantity=reserved)then issue:=0;reason:='material_custody_review';end if;
 available:=greatest(available-(select coalesce(sum(quantity),0)from public.inventory_reservations where factory_id=f and material_id=m.material_id and released_at is null),0);
 else select greatest(coalesce(b.on_hand-b.reserved,0),0)into available from public.finished_goods_balances b where factory_id=f and product_id=m.product_id and unit=m.unit;issue:=reserved;end if;
 available:=coalesce(available,0);
 select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 due:=o.status='active'or(o.status='planned'and o.start_time is not null and o.start_time<=clock_timestamp()+lead_seconds*interval '1 second');
 state:=coalesce(private.material_progress(f,r)->>'status',m.status);
 if m.status in('CANCELLED','REJECTED')then state:=m.status;reason:='material_request_closed';
 elsif o.status in('completed','cancelled')then state:=case when coalesce(p.issued,0)<m.quantity or held>0 then 'CLOSED_REVIEW'else 'CLOSED'end;reason:=case when state='CLOSED_REVIEW'then 'material_order_reconciliation'else 'material_order_closed'end;
 elsif o.start_time is null or o.line_id is null then reason:='material_plan_required';
 elsif not due then state:='AWAITING_RESERVATION';reason:='material_outside_window';
 elsif exists(select 1 from private.material_preparation_jobs where factory_id=f and item_id=o.id and warning is not null)and m.automatic_requirement_key is not null then reason:=(select warning from private.material_preparation_jobs where factory_id=f and item_id=o.id);
 elsif coalesce(p.awaiting,false)then state:='REQUESTED';reason:='material_recheck_required';recheck:=true;
 end if;
 if private.output_work_held(f,o.id)then reason:='output_quality_hold';recheck:=false;end if;
 return jsonb_build_object('state',state,'reason',reason,'order_status',o.status,'production_held',trim_scale(held)::text,'outstanding',trim_scale(greatest(m.quantity-coalesce(p.issued,0),0))::text,'can_recheck',recheck,
 'eligible',jsonb_build_object('RESERVE',trim_scale(case when reason is null then least(pending,available)else 0 end)::text,'ISSUE',trim_scale(case when reason is null then greatest(issue,0)else 0 end)::text,'RELEASE',trim_scale(reserved)::text,'RETURN',trim_scale(held)::text,'CONSUME',trim_scale(case when o.status='active'then held else 0 end)::text));
end$$;
revoke all on function private.material_action_context(uuid,uuid)from public,anon,authenticated,service_role;

create function private.material_start_readiness(f uuid,i uuid)returns jsonb language plpgsql stable set search_path='' as $$
declare o public.production_orders;req jsonb;x jsonb;rows jsonb:='[]';held numeric;missing numeric;ready boolean:=true;reason text;name text;name_ar text;begin
 select *into o from public.production_orders where factory_id=f and id=i;if not found then raise exception 'not_found'using errcode='P0002';end if;
 req:=private.material_requirement_inputs(f,i);reason:=req->>'warning';
 -- Existing completion/rework source-lot safeguards own these inputs; do not explode raw recipe twice.
 if req->>'existing_source_work'='true'then return jsonb_build_object('ready',true,'reason',null,'scope','EXISTING_SOURCE_WORK','rows',rows);end if;
 if reason is not null then return jsonb_build_object('ready',false,'reason',reason,'rows',rows);end if;
 if exists(select 1 from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=f and m.production_item_id=i and m.automatic_requirement_key is not null and m.status not in('CANCELLED','REJECTED')and p.requirement is distinct from req)then return jsonb_build_object('ready',false,'reason','material_requirement_review','rows',rows);end if;
 for x in select value from jsonb_array_elements(req->'inputs')loop
 select coalesce(sum(p.issued-p.consumed),0)into held from public.material_requests m join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=f and m.production_item_id=i and m.status not in('CANCELLED','REJECTED')and m.unit=x->>'unit'and(case when x->>'kind'='material'then m.material_id=(x->>'id')::uuid else m.product_id=(x->>'id')::uuid end);
 missing:=greatest((x->>'quantity')::numeric-held,0);ready:=ready and missing=0;
 if x->>'kind'='material'then select m.name,m.name_ar into name,name_ar from public.materials m where m.factory_id=f and m.id=(x->>'id')::uuid;else select p.name,p.name_ar into name,name_ar from public.products p where p.factory_id=f and p.id=(x->>'id')::uuid;end if;
 rows:=rows||jsonb_build_array(jsonb_build_object('id',x->>'id','kind',x->>'kind','name',name,'name_ar',name_ar,'required',x->>'quantity','production_held',trim_scale(held)::text,'missing',trim_scale(missing)::text,'unit',x->>'unit'));
 end loop;
 return jsonb_build_object('ready',ready,'reason',case when not ready then 'material_handover_required'end,'required_output',o.target_quantity::text,'unit',o.unit,'recipe',req->'recipe','recipe_version',req->'recipe_version','rows',rows);
end$$;
revoke all on function private.material_start_readiness(uuid,uuid)from public,anon,authenticated,service_role;

create function private.material_start_guard()returns trigger language plpgsql security definer set search_path=''as $$declare readiness jsonb;begin
 if new.status='active'and(old.status is distinct from 'active'or old.actual_start is null and new.actual_start is not null)then
 if current_setting('transaction_isolation') not in('read committed','read uncommitted')then raise exception 'execution_readiness_stale'using errcode='40001';end if;
 perform private.require_permission(new.factory_id,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(new.factory_id::text,0));perform private.maintenance_planning_lock(new.factory_id);
 if row(new.product_id,new.unit,new.target_quantity,new.request_id)is distinct from row(old.product_id,old.unit,old.target_quantity,old.request_id)then raise exception 'execution_use_command';end if;
 readiness:=private.material_start_readiness(new.factory_id,new.id);
 if not coalesce((readiness->>'ready')::boolean,false)then raise exception 'production_material_not_ready'using errcode='22023',detail=readiness::text;end if;
 end if;return new;end$$;
revoke all on function private.material_start_guard()from public,anon,authenticated,service_role;
create trigger a_material_start_guard before update on public.production_orders for each row execute function private.material_start_guard();

CREATE OR REPLACE FUNCTION public.start_product_item(factory uuid, item uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform private.require_permission(factory,'orders','edit');
 if current_setting('transaction_isolation') not in ('read committed','read uncommitted') then
 raise exception 'execution_readiness_stale' using errcode='40001';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
 perform private.maintenance_planning_lock(factory);
 perform private.require_permission(factory,'orders','edit');
 return private.start_product_item_before_readiness(factory,item);
end$function$
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
end$function$
;

CREATE OR REPLACE FUNCTION private.reconcile_material_item(f uuid, i uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare o public.production_orders;requirements jsonb;x jsonb;m public.material_requests;p private.material_request_progress;key text;manual numeric;need numeric;label text;created integer:=0;warning text;lead_seconds numeric;
begin
 select *into o from public.production_orders where factory_id=f and id=i for update;if not found then return 0;end if;
 select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 if o.status in('completed','cancelled')or(o.status='planned'and(o.start_time is null or o.start_time>clock_timestamp()+lead_seconds*interval '1 second'))then perform private.release_material_preparation(f,i);insert into private.material_preparation_jobs values(f,i,null,clock_timestamp())on conflict(factory_id,item_id)do update set warning=null,checked_at=excluded.checked_at;return 0;end if;
 if o.status='active'and o.actual_start is not null and o.actual_finish is null then
 requirements:=private.material_requirement_inputs(f,i);warning:=requirements->>'warning';
 if private.output_work_held(f,i)then warning:='output_quality_hold';end if;
 if exists(select 1 from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.automatic_requirement_key is not null and r.status not in('CANCELLED','REJECTED')and mp.requirement is distinct from requirements)then warning:='material_requirement_review';end if;
 insert into private.material_preparation_jobs values(f,i,warning,clock_timestamp())on conflict(factory_id,item_id)do update set warning=excluded.warning,checked_at=excluded.checked_at;
 if warning is not null then return 0;end if;
 for m in select r.*from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.status not in('CANCELLED','REJECTED')and mp.awaiting loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end loop;
 return 0;end if;
 if o.status<>'planned'or o.actual_start is not null then return 0;end if;
 for m in select r.*from public.material_requests r join private.material_request_progress mp on mp.factory_id=r.factory_id and mp.request_id=r.id where r.factory_id=f and r.production_item_id=i and r.automatic_requirement_key is null and r.status not in('CANCELLED','REJECTED')and mp.awaiting loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end loop;
 requirements:=private.material_requirement_inputs(f,i);warning:=requirements->>'warning';if private.output_work_held(f,i)then warning:='output_quality_hold';end if;
 -- Validate the whole stage before creating any part of a requirement.
 if warning is null and requirements->>'existing_source_work'is distinct from 'true'then
 for m in select *from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is not null loop
 select *into p from private.material_request_progress where factory_id=f and request_id=m.id;
 if p.requirement is distinct from requirements or m.status in('CANCELLED','REJECTED')then warning:='material_requirement_review';exit;end if;
 end loop;
 for x in select value from jsonb_array_elements(requirements->'inputs')loop
 key:=(x->>'kind')||':'||(x->>'id')||':'||(x->>'unit');
 select coalesce(sum(quantity),0)into manual from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is null and status not in('CANCELLED','REJECTED')and unit=x->>'unit'and(case when x->>'kind'='material'then material_id=(x->>'id')::uuid else product_id=(x->>'id')::uuid end);
 select *into m from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key=key;
 if manual>(x->>'quantity')::numeric or(m.id is not null and m.quantity+manual<>(x->>'quantity')::numeric)then warning:='material_requirement_review';end if;
 end loop;end if;
 insert into private.material_preparation_jobs values(f,i,warning,clock_timestamp())on conflict(factory_id,item_id)do update set warning=excluded.warning,checked_at=excluded.checked_at;
 if warning is not null or requirements->>'existing_source_work'='true'then return 0;end if;
 for x in select value from jsonb_array_elements(requirements->'inputs')loop
 key:=(x->>'kind')||':'||(x->>'id')||':'||(x->>'unit');select *into m from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key=key;
 if found then select *into p from private.material_request_progress where factory_id=f and request_id=m.id;if p.awaiting then
 update private.material_request_progress set awaiting=false where factory_id=f and request_id=m.id;update public.material_requests set revision=revision+1 where id=m.id;perform private.material_event(f,m.id,i,gen_random_uuid(),'REACTIVATED','{}',to_jsonb(p));end if;continue;end if;
 select coalesce(sum(quantity),0)into manual from public.material_requests where factory_id=f and production_item_id=i and automatic_requirement_key is null and status not in('CANCELLED','REJECTED')and unit=x->>'unit'and(case when x->>'kind'='material'then material_id=(x->>'id')::uuid else product_id=(x->>'id')::uuid end);
 need:=(x->>'quantity')::numeric-manual;if need<=0 then continue;end if;
 if x->>'kind'='material'then select name into label from public.materials where factory_id=f and id=(x->>'id')::uuid;else select name into label from public.products where factory_id=f and id=(x->>'id')::uuid;end if;
 insert into public.material_requests(factory_id,material_id,product_id,production_item_id,item_name,quantity,unit,note,requested_by,requested_by_name,automatic_requirement_key)values(f,case when x->>'kind'='material'then(x->>'id')::uuid end,case when x->>'kind'='product'then(x->>'id')::uuid end,i,label,need,x->>'unit','Automatic stage-specific material preparation',null,'System',key)returning *into m;
 insert into private.material_request_progress(factory_id,request_id,requirement)values(f,m.id,requirements);perform private.material_event(f,m.id,i,gen_random_uuid(),'REQUESTED',jsonb_build_object('source','SYSTEM'),null);created:=created+1;
 end loop;return created;end$function$
;

CREATE OR REPLACE FUNCTION public.production_material_action(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare m public.material_requests;p private.material_request_progress;prior private.material_preparation_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);previous jsonb;q numeric;context jsonb;available numeric;result jsonb;move uuid;pick jsonb;total numeric;source public.finished_goods_sources;qty numeric;entry uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='CONSUME'then perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');else perform private.require_permission(factory,'warehouse','issue');end if;
 if operation is null or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>16000 or operation not in('RESERVE','ISSUE','CONSUME','RETURN','RELEASE','RECHECK')or exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','allocations','entry','physical_confirmation','reason'))then raise exception 'material_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into prior from private.material_preparation_events where factory_id=factory and retry_id=production_material_action.request_id;
 if found then if prior.actor is distinct from auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_state;end if;
 select *into m from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid for update;
 if m.id is null or m.production_item_id is null or m.lot_id is not null or m.status in('CANCELLED','REJECTED')then raise exception 'material_invalid'using errcode='22023';end if;
 if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;
 select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id for update;
 if not found then if m.status<>'REQUESTED'then raise exception 'material_custody_review'using errcode='22023';end if;insert into private.material_request_progress(factory_id,request_id,requirement)values(factory,m.id,jsonb_build_object('manual',true));select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;end if;
 if private.output_work_held(factory,m.production_item_id)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation='RECHECK'then
 previous:=private.material_progress(factory,m.id);context:=private.material_action_context(factory,m.id);
 if not coalesce((context->>'can_recheck')::boolean,false)then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 perform private.reconcile_material_item(factory,m.production_item_id);context:=private.material_action_context(factory,m.id);
 if context->>'reason'is not null then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 return private.material_event(factory,m.id,m.production_item_id,request_id,operation,intent,previous);end if;
 if operation in('RESERVE','ISSUE')then perform private.reconcile_material_item(factory,m.production_item_id);select *into m from public.material_requests where factory_id=factory and id=m.id;select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;end if;
 if operation in('RESERVE','ISSUE')and(p.awaiting or(m.automatic_requirement_key is not null and exists(select 1 from private.material_preparation_jobs where factory_id=factory and item_id=m.production_item_id and warning is not null)))then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;
 if q<=0 or q::text in('NaN','Infinity','-Infinity')then raise exception 'material_invalid'using errcode='22023';end if;
 context:=private.material_action_context(factory,m.id);
 if operation in('RESERVE','ISSUE')and context->>'reason'is not null then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if q>coalesce((context->'eligible'->>operation)::numeric,0)then raise exception 'material_quantity'using errcode='22023';end if;
 previous:=private.material_progress(factory,m.id);
 if m.product_id is not null then
 if jsonb_typeof(payload->'allocations')is distinct from 'array'or jsonb_array_length(payload->'allocations')>100 or jsonb_array_length(payload->'allocations')=0 then raise exception 'source_identity'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(payload->'allocations')x where jsonb_typeof(x)<>'object'or exists(select 1 from jsonb_object_keys(x)k where k not in('source_id','quantity'))or x->>'source_id'is null or jsonb_typeof(x->'quantity')<>'string'or x->>'quantity'!~'^[0-9]+([.][0-9]+)?$'or(x->>'quantity')::numeric<=0)or(select count(distinct x->>'source_id')<>count(*)from jsonb_array_elements(payload->'allocations')x)then raise exception 'source_identity'using errcode='22023';end if;
 select sum((x->>'quantity')::numeric)into total from jsonb_array_elements(payload->'allocations')x;if total<>q then raise exception 'source_quantity'using errcode='22023';end if;
 end if;
 if m.product_id is not null and operation<>'RETURN'and exists(select 1 from jsonb_array_elements(payload->'allocations')a join public.finished_goods_sources s on s.factory_id=factory and s.id=(a->>'source_id')::uuid join private.manufactured_outputs o on o.factory_id=factory and o.entry_id=s.entry_id join private.output_hold_rows(factory)h on h.output_id=o.id and h.finished)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation='RESERVE'then
 if q>m.quantity-p.issued-p.reserved then raise exception 'material_quantity'using errcode='22023';end if;
 if m.material_id is not null then
 select coalesce(sum(quantity),0)-(select coalesce(sum(quantity),0)from public.inventory_reservations where factory_id=factory and material_id=m.material_id and released_at is null)into available from public.inventory_transactions where factory_id=factory and material_id=m.material_id;
 if available<q then raise exception 'material_shortage'using errcode='22023';end if;
 if p.reservation_id is null then insert into public.inventory_reservations(factory_id,material_id,order_id,quantity)values(factory,m.material_id,m.production_item_id,q)returning id into p.reservation_id;else update public.inventory_reservations set quantity=quantity+q where id=p.reservation_id and released_at is null;if not found then raise exception 'material_changed'using errcode='40001';end if;end if;
 else
 select on_hand-reserved into available from public.finished_goods_balances where factory_id=factory and product_id=m.product_id and unit=m.unit for update;if coalesce(available,0)<q then raise exception 'material_shortage'using errcode='22023';end if;
 for pick in select value from jsonb_array_elements(payload->'allocations')loop select *into source from public.finished_goods_sources where factory_id=factory and id=(pick->>'source_id')::uuid for update;qty:=(pick->>'quantity')::numeric;
 if source.id is null or source.product_id<>m.product_id or source.unit<>m.unit or source.physical_label is null or source.quantity_available-private.source_reserved(factory,source.id)<qty then raise exception 'source_unavailable'using errcode='22023';end if;
 insert into private.material_source_reservations values(factory,m.id,source.id,qty)on conflict on constraint material_source_reservations_pkey do update set quantity=material_source_reservations.quantity+excluded.quantity;
 end loop;update public.finished_goods_balances set reserved=reserved+q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 end if;
 update private.material_request_progress set reserved=reserved+q,reservation_id=p.reservation_id where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='ISSUE'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or q>p.reserved then raise exception 'material_quantity'using errcode='22023';end if;move:=gen_random_uuid();
 if m.material_id is not null then
 if p.reservation_id is null then raise exception 'material_changed'using errcode='40001';end if;
 if q=p.reserved then update public.inventory_reservations set released_at=clock_timestamp()where id=p.reservation_id and released_at is null;p.reservation_id:=null;else update public.inventory_reservations set quantity=quantity-q where id=p.reservation_id and released_at is null;end if;
 insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,m.material_id,-q,'material_issue',m.unit,m.id::text,'Measured physical material handover',auth.uid());
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_reservations set quantity=quantity-qty where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity>qty;
 if not found then delete from private.material_source_reservations where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end if;
 insert into private.material_source_custody values(factory,m.id,(pick->>'source_id')::uuid,qty,0)on conflict on constraint material_source_custody_pkey do update set quantity=material_source_custody.quantity+excluded.quantity;
 end loop;
 perform private.source_begin_pick(factory,'material_issue',m.product_id,m.unit,null,payload->'allocations');update public.finished_goods_balances set reserved=reserved-q,on_hand=on_hand-q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by)values(move,factory,m.product_id,m.unit,'material_issue',-q,'Measured physical material handover',m.id::text,auth.uid());perform private.source_end_pick();
 end if;
 update private.material_request_progress set reserved=reserved-q,issued=issued+q,reservation_id=p.reservation_id,last_movement=move where factory_id=factory and material_request_progress.request_id=m.id;
 update public.material_requests set status='ISSUED',issued_by=auth.uid(),issued_at=clock_timestamp(),movement_id=move where id=m.id;
 elsif operation='RELEASE'then
 if length(btrim(coalesce(payload->>'reason','')))<3 or q>p.reserved then raise exception 'material_quantity'using errcode='22023';end if;
 if m.material_id is not null then
 if q=p.reserved then update public.inventory_reservations set released_at=clock_timestamp()where id=p.reservation_id and released_at is null;p.reservation_id:=null;else update public.inventory_reservations set quantity=quantity-q where id=p.reservation_id and released_at is null;end if;if not found then raise exception 'material_changed'using errcode='40001';end if;
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_reservations set quantity=quantity-qty where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity>qty;
 if not found then delete from private.material_source_reservations where factory_id=factory and material_source_reservations.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end if;end loop;update public.finished_goods_balances set reserved=reserved-q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 end if;update private.material_request_progress set reserved=reserved-q,reservation_id=p.reservation_id where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='CONSUME'then
 entry:=(payload->>'entry')::uuid;if q>p.issued-p.consumed or not exists(select 1 from public.production_orders where factory_id=factory and id=m.production_item_id and status='active'and actual_start is not null)or(entry is not null and not exists(select 1 from public.production_entries where factory_id=factory and id=entry and order_id=m.production_item_id and created_at>=m.issued_at))then raise exception 'material_quantity'using errcode='22023';end if;
 if m.product_id is not null then for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set consumed=consumed+qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end loop;end if;
 update private.material_request_progress set consumed=consumed+q where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='RETURN'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or length(btrim(coalesce(payload->>'reason','')))<3 or q>p.issued-p.consumed then raise exception 'material_quantity'using errcode='22023';end if;move:=gen_random_uuid();
 if m.material_id is not null then insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,m.material_id,q,'material_return',m.unit,m.id::text,payload->>'reason',auth.uid());
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set quantity=quantity-qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;update public.finished_goods_sources set quantity_available=quantity_available+qty where factory_id=factory and id=(pick->>'source_id')::uuid;end loop;
 perform private.source_begin_pick(factory,'material_return',m.product_id,m.unit,null,payload->'allocations');update public.finished_goods_balances set on_hand=on_hand+q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by)values(move,factory,m.product_id,m.unit,'material_return',q,payload->>'reason',m.id::text,auth.uid());perform private.source_end_pick();
 end if;
 update private.material_request_progress set issued=issued-q,last_movement=move where factory_id=factory and material_request_progress.request_id=m.id;update public.material_requests set status=case when p.issued-q>0 then 'ISSUED'else 'REQUESTED'end where id=m.id;
 end if;
 update public.material_requests set revision=revision+1 where id=m.id;result:=private.material_event(factory,m.id,m.production_item_id,request_id,operation,intent,previous,entry);
 return result;
end$function$
;

CREATE OR REPLACE FUNCTION public.production_material_work(factory uuid, audience text, item uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare rows jsonb;warnings jsonb;begin
 perform private.material_audience(factory,audience);if item is not null and not exists(select 1 from public.production_orders where factory_id=factory and id=item)then raise exception 'material_invalid'using errcode='22023';end if;
 select coalesce(jsonb_agg((jsonb_build_object('id',m.id,'item',m.production_item_id,'code',o.code,'name',m.item_name,'quantity',trim_scale(m.quantity)::text,'unit',m.unit,'material',m.material_id,'product',m.product_id,'revision',m.revision,'managed',p.request_id is not null,'automatic',m.automatic_requirement_key is not null,'reserved',trim_scale(coalesce(p.reserved,0))::text,'issued',trim_scale(coalesce(p.issued,case when m.status in('ISSUED','RECEIVED')then m.quantity else 0 end))::text,'consumed',trim_scale(coalesce(p.consumed,0))::text,'awaiting',coalesce(p.awaiting,false),'state',coalesce(private.material_progress(factory,m.id)->>'status',m.status),'available',case when m.material_id is not null then trim_scale((select coalesce(sum(t.quantity),0)from public.inventory_transactions t where t.factory_id=factory and t.material_id=m.material_id)-(select coalesce(sum(r.quantity),0)from public.inventory_reservations r where r.factory_id=factory and r.material_id=m.material_id and r.released_at is null))::text else(select trim_scale(b.on_hand-b.reserved)::text from public.finished_goods_balances b where b.factory_id=factory and b.product_id=m.product_id and b.unit=m.unit)end,'reservations',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity)::text)order by r.source_id),'[]')from private.material_source_reservations r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id),'custody',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity-r.consumed)::text)order by r.source_id),'[]')from private.material_source_custody r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id)) || private.material_action_context(factory,m.id)) order by o.code,m.id),'[]')into rows from public.material_requests m join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id left join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=factory and m.lot_id is null and m.status not in('CANCELLED','REJECTED')and(item is null or m.production_item_id=item);
 select coalesce(jsonb_agg(jsonb_build_object('item',j.item_id,'code',o.code,'product',p.name,'warning',j.warning)order by o.code),'[]')into warnings from private.material_preparation_jobs j join public.production_orders o on o.factory_id=j.factory_id and o.id=j.item_id join public.products p on p.factory_id=o.factory_id and p.id=o.product_id where j.factory_id=factory and j.warning is not null and(item is null or j.item_id=item)and o.status='planned';return jsonb_build_object('rows',rows,'warnings',warnings);end$function$
;
