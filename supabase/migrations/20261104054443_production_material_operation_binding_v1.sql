begin;
CREATE OR REPLACE FUNCTION public.production_material_action(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare m public.material_requests;p private.material_request_progress;prior private.material_preparation_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);previous jsonb;q numeric;available numeric;result jsonb;move uuid;pick jsonb;total numeric;source public.finished_goods_sources;qty numeric;entry uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='CONSUME'then perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');else perform private.require_permission(factory,'warehouse','issue');end if;
 if request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>16000 or operation not in('RESERVE','ISSUE','CONSUME','RETURN')or exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','allocations','entry','physical_confirmation','reason'))then raise exception 'material_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into prior from private.material_preparation_events where factory_id=factory and retry_id=production_material_action.request_id;
 if found then if prior.actor is distinct from auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_state;end if;
 select *into m from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid for update;
 if m.id is null or m.production_item_id is null or m.lot_id is not null or m.status in('CANCELLED','REJECTED')then raise exception 'material_invalid'using errcode='22023';end if;
 if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;
 select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id for update;
 if not found then if m.status<>'REQUESTED'then raise exception 'material_custody_review'using errcode='22023';end if;insert into private.material_request_progress(factory_id,request_id,requirement)values(factory,m.id,jsonb_build_object('manual',true));select *into p from private.material_request_progress where factory_id=factory and request_id=m.id;end if;
 if private.output_work_held(factory,m.production_item_id)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation in('RESERVE','ISSUE')and(p.awaiting or exists(select 1 from private.material_preparation_jobs where factory_id=factory and item_id=m.production_item_id and warning is not null))then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if jsonb_typeof(payload->'quantity')<>'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;
 if q<=0 or q::text in('NaN','Infinity','-Infinity')then raise exception 'material_invalid'using errcode='22023';end if;
 previous:=private.material_progress(factory,m.id);
 if m.product_id is not null then
 if jsonb_typeof(payload->'allocations')is distinct from 'array'or jsonb_array_length(payload->'allocations')>100 or jsonb_array_length(payload->'allocations')=0 then raise exception 'source_identity'using errcode='22023';end if;
 if exists(select 1 from jsonb_array_elements(payload->'allocations')x where jsonb_typeof(x)<>'object'or exists(select 1 from jsonb_object_keys(x)k where k not in('source_id','quantity'))or x->>'source_id'is null or jsonb_typeof(x->'quantity')<>'string'or x->>'quantity'!~'^[0-9]+([.][0-9]+)?$'or(x->>'quantity')::numeric<=0)or(select count(distinct x->>'source_id')<>count(*)from jsonb_array_elements(payload->'allocations')x)then raise exception 'source_identity'using errcode='22023';end if;
 select sum((x->>'quantity')::numeric)into total from jsonb_array_elements(payload->'allocations')x;if total<>q then raise exception 'source_quantity'using errcode='22023';end if;
 end if;
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
 elsif operation='CONSUME'then
 entry:=(payload->>'entry')::uuid;if q>p.issued-p.consumed or not exists(select 1 from public.production_entries where factory_id=factory and id=entry and order_id=m.production_item_id)then raise exception 'material_quantity'using errcode='22023';end if;
 if m.product_id is not null then for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set consumed=consumed+qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;end loop;end if;
 update private.material_request_progress set consumed=consumed+q where factory_id=factory and material_request_progress.request_id=m.id;
 elsif operation='RETURN'then
 if payload->'physical_confirmation'is distinct from 'true'::jsonb or length(btrim(coalesce(payload->>'reason','')))<3 or q>p.issued-p.consumed then raise exception 'material_quantity'using errcode='22023';end if;move:=gen_random_uuid();
 if m.material_id is not null then insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by)values(move,factory,m.material_id,q,'material_return',m.unit,m.id::text,payload->>'reason',auth.uid());
 else
 for pick in select value from jsonb_array_elements(payload->'allocations')loop qty:=(pick->>'quantity')::numeric;update private.material_source_custody set quantity=quantity-qty where factory_id=factory and material_source_custody.request_id=m.id and source_id=(pick->>'source_id')::uuid and quantity-consumed>=qty;if not found then raise exception 'source_unavailable'using errcode='22023';end if;update public.finished_goods_sources set quantity_available=quantity_available+qty where factory_id=factory and id=(pick->>'source_id')::uuid;end loop;
 update public.finished_goods_balances set on_hand=on_hand+q where factory_id=factory and product_id=m.product_id and unit=m.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by)values(move,factory,m.product_id,m.unit,'material_return',q,payload->>'reason',m.id::text,auth.uid());
 end if;
 update private.material_request_progress set issued=issued-q,last_movement=move where factory_id=factory and material_request_progress.request_id=m.id;update public.material_requests set status=case when p.issued-q>0 then 'ISSUED'else 'REQUESTED'end where id=m.id;
 end if;
 update public.material_requests set revision=revision+1 where id=m.id;result:=private.material_event(factory,m.id,m.production_item_id,request_id,operation,intent,previous,entry);
 return result;
end$function$;
commit;
