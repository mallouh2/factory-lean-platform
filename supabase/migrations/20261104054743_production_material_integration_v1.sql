begin;
CREATE OR REPLACE FUNCTION public.production_material_action(factory uuid, operation text, payload jsonb, request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare m public.material_requests;p private.material_request_progress;prior private.material_preparation_events;intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);previous jsonb;q numeric;available numeric;result jsonb;move uuid;pick jsonb;total numeric;source public.finished_goods_sources;qty numeric;entry uuid;begin
 perform private.require_permission(factory,'factory','view');
 if operation='CONSUME'then perform private.require_permission(factory,'orders','edit');perform private.require_permission(factory,'orders','view');else perform private.require_permission(factory,'warehouse','issue');end if;
 if operation is null or request_id is null or payload is null or jsonb_typeof(payload)<>'object'or octet_length(payload::text)>16000 or operation not in('RESERVE','ISSUE','CONSUME','RETURN','RELEASE')or exists(select 1 from jsonb_object_keys(payload)k where k not in('id','revision','quantity','allocations','entry','physical_confirmation','reason'))then raise exception 'material_invalid'using errcode='22023';end if;
 perform pg_advisory_xact_lock(hashtextextended(factory::text,0));perform pg_advisory_xact_lock(hashtextextended(factory::text||':structure',0));
 select *into prior from private.material_preparation_events where factory_id=factory and retry_id=production_material_action.request_id;
 if found then if prior.actor is distinct from auth.uid()or prior.intent<>intent then raise exception 'request_conflict'using errcode='40001';end if;return prior.after_state;end if;
 select *into m from public.material_requests where factory_id=factory and id=(payload->>'id')::uuid for update;
 if m.id is null or m.production_item_id is null or m.lot_id is not null or m.status in('CANCELLED','REJECTED')then raise exception 'material_invalid'using errcode='22023';end if;
 if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;
 select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id for update;
 if not found then if m.status<>'REQUESTED'then raise exception 'material_custody_review'using errcode='22023';end if;insert into private.material_request_progress(factory_id,request_id,requirement)values(factory,m.id,jsonb_build_object('manual',true));select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;end if;
 if private.output_work_held(factory,m.production_item_id)then raise exception 'output_quality_hold'using errcode='22023';end if;
 if operation in('RESERVE','ISSUE')then perform private.reconcile_material_item(factory,m.production_item_id);select *into m from public.material_requests where factory_id=factory and id=m.id;select *into p from private.material_request_progress where factory_id=factory and material_request_progress.request_id=m.id;if m.revision is distinct from(payload->>'revision')::int then raise exception 'material_changed'using errcode='40001';end if;end if;
 if operation in('RESERVE','ISSUE')and(p.awaiting or(m.automatic_requirement_key is not null and exists(select 1 from private.material_preparation_jobs where factory_id=factory and item_id=m.production_item_id and warning is not null)))then raise exception 'material_preparation_unavailable'using errcode='22023';end if;
 if jsonb_typeof(payload->'quantity')is distinct from 'string'or payload->>'quantity'!~'^[0-9]+([.][0-9]+)?$'then raise exception 'material_invalid'using errcode='22023';end if;q:=(payload->>'quantity')::numeric;
 if q<=0 or q::text in('NaN','Infinity','-Infinity')then raise exception 'material_invalid'using errcode='22023';end if;
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
end$function$;
CREATE OR REPLACE FUNCTION public.supply_command(factory uuid, action text, payload jsonb, request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform private.require_permission(factory,'factory','view');
 if action='material_change'and exists(select 1 from private.material_request_progress where factory_id=factory and material_request_progress.request_id=(payload->>'id')::uuid)then raise exception 'material_use_preparation_workflow'using errcode='22023';end if;
 return private.supply_before_material_preparation(factory,action,payload,request_id);end$function$;
CREATE OR REPLACE FUNCTION private.material_progress(f uuid, r uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$select to_jsonb(p)||jsonb_build_object('revision',m.revision,'quantity',m.quantity::text,'unit',m.unit,'item',m.production_item_id,'name',m.item_name,'status',case when p.awaiting then 'AWAITING_RESERVATION'when p.consumed=m.quantity then 'CLOSED'when p.issued=m.quantity then 'ISSUED'when p.issued>0 then 'PARTIALLY_ISSUED'when p.reserved=m.quantity then 'RESERVED'when p.reserved>0 then 'PARTIALLY_RESERVED'else 'REQUESTED'end)from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=f and p.request_id=r$function$;
CREATE OR REPLACE FUNCTION private.source_movement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare ctx private.finished_goods_pick_context;src public.finished_goods_sources;e public.production_entries;o public.production_orders;
 pick jsonb;pos integer; amount numeric;used numeric;total numeric:=0;needed numeric;pending numeric;released numeric;r record;
begin
 perform private.fulfillment_lock(new.factory_id);
 insert into private.finished_goods_unattributed values(new.factory_id,new.product_id,new.unit,0) on conflict do nothing;
 if new.stock_delta>0 and new.kind='material_return'then
 select *into ctx from private.finished_goods_pick_context where backend=pg_backend_pid()and transaction_id=txid_current();
 if ctx.factory_id is distinct from new.factory_id or ctx.actor_id is distinct from auth.uid()or ctx.kind<>'material_return'or ctx.product_id is distinct from new.product_id or ctx.unit is distinct from new.unit then raise exception 'source_identity';end if;
 for pick,pos in select value,ordinality::int from jsonb_array_elements(ctx.picks)with ordinality loop
 amount:=(pick->>'quantity')::numeric;total:=total+amount;
 if not exists(select 1 from public.material_requests m join private.material_source_custody c on c.factory_id=m.factory_id and c.request_id=m.id where m.id::text=new.external_reference and m.factory_id=new.factory_id and m.product_id=new.product_id and m.unit=new.unit and c.source_id=(pick->>'source_id')::uuid)then raise exception 'source_identity';end if;
 insert into public.finished_goods_source_allocations(factory_id,movement_id,source_id,quantity)values(new.factory_id,new.id,(pick->>'source_id')::uuid,amount);
 insert into private.finished_goods_pick_usage values(pg_backend_pid(),txid_current(),pos,amount);
 end loop;
 if total<>new.stock_delta then raise exception 'source_quantity';end if;
 elsif new.stock_delta>0 then
  update private.finished_goods_unattributed set quantity=quantity+new.stock_delta where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit;
  if new.entry_id is not null and new.kind in ('production_receipt','production_correction') then
   select * into e from public.production_entries where factory_id=new.factory_id and id=new.entry_id;
   select * into o from public.production_orders where factory_id=new.factory_id and id=e.order_id;
   if o.product_id is distinct from new.product_id or e.unit is distinct from new.unit then raise exception 'source_identity';end if;
   insert into public.finished_goods_sources(factory_id,entry_id,item_id,product_id,unit,line_id,work_center_id,shift_id,recorded_at,quantity_credited,shift_name,shift_name_ar,shift_date,factory_timezone,origin_occurrence_key,origin_execution_key)
   values(new.factory_id,e.id,o.id,o.product_id,e.unit,e.line_id,e.work_center_id,e.original_shift_id,e.created_at,new.stock_delta,
    case when e.attribution_version=1 then (select name from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select name from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id) end,
    case when e.attribution_version=1 then (select name_ar from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select name_ar from public.production_shifts where factory_id=e.factory_id and id=e.original_shift_id) end,
    case when e.attribution_version=1 then (select business_date from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else private.source_shift_date(e.factory_id,e.original_shift_id,e.created_at) end,
    case when e.attribution_version=1 then (select timezone from private.production_shift_occurrences where factory_id=e.factory_id and occurrence_key=e.original_occurrence_key) else (select timezone from public.factories where id=e.factory_id) end,e.original_occurrence_key,e.execution_key)
   on conflict(factory_id,entry_id) do update set quantity_credited=public.finished_goods_sources.quantity_credited+excluded.quantity_credited;
  end if;
 elsif new.stock_delta<0 then
  needed:=-new.stock_delta;
  select * into ctx from private.finished_goods_pick_context where backend=pg_backend_pid() and transaction_id=txid_current();
  if found then
   if ctx.factory_id<>new.factory_id or ctx.actor_id is distinct from auth.uid() or ctx.kind<>new.kind
   or (ctx.product_id is not null and ctx.product_id<>new.product_id) or (ctx.unit is not null and ctx.unit<>new.unit)
   or (ctx.entry_id is not null and ctx.entry_id is distinct from new.entry_id) then raise exception 'source_identity';end if;
   for pick,pos in select value,ordinality::integer from jsonb_array_elements(ctx.picks) with ordinality loop
    if new.kind='dispatch' and (pick->>'sales_line_id')::uuid is distinct from new.sales_line_id then continue;end if;
    select coalesce(quantity,0) into used from private.finished_goods_pick_usage where backend=pg_backend_pid() and transaction_id=txid_current() and position=pos;
    amount:=(pick->>'quantity')::numeric-coalesce(used,0);
    if amount<=0 then continue;end if;
    if amount>needed-total then raise exception 'source_quantity';end if;
    if pick->>'source_id' is null then if private.output_pool_held(new.factory_id,new.product_id,new.unit) then raise exception 'output_quality_hold';end if;
     update private.finished_goods_unattributed set quantity=quantity-amount where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=amount;
     if not found then raise exception 'source_unavailable';end if;
    else
     select * into src from public.finished_goods_sources where factory_id=new.factory_id and id=(pick->>'source_id')::uuid for update;
     if private.output_source_held(new.factory_id,src.entry_id) and not private.output_reconcile_pick_allowed(new.factory_id,new.entry_id,new.kind,new.stock_delta,src.id) then raise exception 'output_quality_hold';end if; if src.id is null or src.product_id<>new.product_id or src.unit<>new.unit or src.physical_label is null
     or src.quantity_available-private.source_reserved(new.factory_id,src.id)<amount then raise exception 'source_unavailable';end if;
     if new.kind in ('production_correction','quality_rejection') and src.entry_id is distinct from new.entry_id then raise exception 'source_identity';end if;
     update public.finished_goods_sources set quantity_available=quantity_available-amount,
      quantity_identified=quantity_identified-case when new.kind='production_correction' then amount else 0 end where id=src.id;
    end if;
    insert into public.finished_goods_source_allocations(factory_id,movement_id,source_id,quantity) values(new.factory_id,new.id,(pick->>'source_id')::uuid,amount);
    insert into private.finished_goods_pick_usage values(pg_backend_pid(),txid_current(),pos,amount)
     on conflict(backend,transaction_id,position) do update set quantity=private.finished_goods_pick_usage.quantity+excluded.quantity;
    total:=total+amount;
   end loop;
   if total<>needed then raise exception 'source_quantity';end if;
  else
   -- Old clients can still use pooled stock, but cannot silently pick an identified batch.
 if private.output_pool_held(new.factory_id,new.product_id,new.unit) then raise exception 'output_quality_hold';end if;
   update private.finished_goods_unattributed set quantity=quantity-needed where factory_id=new.factory_id and product_id=new.product_id and unit=new.unit and quantity>=needed;
   if not found then raise exception 'source_selection_required';end if;
   insert into public.finished_goods_source_allocations(factory_id,movement_id,quantity) values(new.factory_id,new.id,needed);
  end if;
  if new.kind='production_correction' then
   if exists(select 1 from public.finished_goods_sources where factory_id=new.factory_id and entry_id=new.entry_id) then
    update public.finished_goods_sources set quantity_credited=greatest(quantity_credited-needed,0)
     where factory_id=new.factory_id and entry_id=new.entry_id and greatest(quantity_credited-needed,0)>=quantity_identified;
    if not found then raise exception 'source_correction_unavailable';end if;
   end if;
  end if;
 end if;
 if new.reserved_delta<0 then
  -- Release unallocated commitments first; release identified assignments only as needed.
  select coalesce(sum(quantity),0) into pending from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id;
  select greatest(pending-coalesce(quantity,0),0) into released from public.finished_goods_reservations where factory_id=new.factory_id and line_id=new.sales_line_id;
  released:=coalesce(released,pending);
  for r in select * from public.finished_goods_source_reservations where factory_id=new.factory_id and sales_line_id=new.sales_line_id order by source_id for update loop
   amount:=least(released,r.quantity);exit when amount<=0;
   if amount=r.quantity then delete from public.finished_goods_source_reservations where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;
   else update public.finished_goods_source_reservations set quantity=quantity-amount where factory_id=r.factory_id and sales_line_id=r.sales_line_id and source_id=r.source_id;end if;
   released:=released-amount;
  end loop;
 end if;
 return new;
end$function$;

create function private.material_audience(f uuid,a text)returns void language plpgsql stable set search_path='' as $$begin perform private.require_permission(f,'factory','view');if a='WAREHOUSE'then perform private.require_permission(f,'warehouse','view');elsif a='PRODUCTION'then perform private.require_permission(f,'orders','view');perform private.require_permission(f,'lines','view');else raise exception 'permission_denied'using errcode='42501';end if;end$$;
create function public.production_material_work(factory uuid,audience text,item uuid default null)returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;warnings jsonb;begin
 perform private.material_audience(factory,audience);if item is not null and not exists(select 1 from public.production_orders where factory_id=factory and id=item)then raise exception 'material_invalid'using errcode='22023';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'item',m.production_item_id,'code',o.code,'name',m.item_name,'quantity',trim_scale(m.quantity)::text,'unit',m.unit,'material',m.material_id,'product',m.product_id,'revision',m.revision,'managed',p.request_id is not null,'automatic',m.automatic_requirement_key is not null,'reserved',trim_scale(coalesce(p.reserved,0))::text,'issued',trim_scale(coalesce(p.issued,case when m.status in('ISSUED','RECEIVED')then m.quantity else 0 end))::text,'consumed',trim_scale(coalesce(p.consumed,0))::text,'awaiting',coalesce(p.awaiting,false),'state',coalesce(private.material_progress(factory,m.id)->>'status',m.status),'available',case when m.material_id is not null then trim_scale((select coalesce(sum(t.quantity),0)from public.inventory_transactions t where t.factory_id=factory and t.material_id=m.material_id)-(select coalesce(sum(r.quantity),0)from public.inventory_reservations r where r.factory_id=factory and r.material_id=m.material_id and r.released_at is null))::text else(select trim_scale(b.on_hand-b.reserved)::text from public.finished_goods_balances b where b.factory_id=factory and b.product_id=m.product_id and b.unit=m.unit)end,'reservations',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity)::text)order by r.source_id),'[]')from private.material_source_reservations r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id),'custody',(select coalesce(jsonb_agg(jsonb_build_object('source_id',r.source_id,'label',z.physical_label,'quantity',trim_scale(r.quantity-r.consumed)::text)order by r.source_id),'[]')from private.material_source_custody r join public.finished_goods_sources z on z.factory_id=r.factory_id and z.id=r.source_id where r.factory_id=factory and r.request_id=m.id))order by o.code,m.id),'[]')into rows from public.material_requests m join public.production_orders o on o.factory_id=m.factory_id and o.id=m.production_item_id left join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=factory and m.lot_id is null and m.status not in('CANCELLED','REJECTED')and(item is null or m.production_item_id=item);
 select coalesce(jsonb_agg(jsonb_build_object('item',j.item_id,'code',o.code,'product',p.name,'warning',j.warning)order by o.code),'[]')into warnings from private.material_preparation_jobs j join public.production_orders o on o.factory_id=j.factory_id and o.id=j.item_id join public.products p on p.factory_id=o.factory_id and p.id=o.product_id where j.factory_id=factory and j.warning is not null and(item is null or j.item_id=item)and o.status='planned';return jsonb_build_object('rows',rows,'warnings',warnings);end$$;
-- Keep the existing notification surface and its effective audience rules.
alter function public.planning_changes_read(uuid,text)set schema private;
alter function private.planning_changes_read(uuid,text)rename to planning_changes_before_materials;
do $binding$begin execute replace(pg_get_functiondef('private.planning_changes_before_materials(uuid,text)'::regprocedure),'planning_changes_read.audience','planning_changes_before_materials.audience');end$binding$;
revoke all on function private.planning_changes_before_materials(uuid,text)from public,anon,authenticated,service_role;
create function public.planning_changes_read(factory uuid,audience text)returns jsonb language plpgsql stable security definer set search_path='' as $$declare legacy jsonb;material jsonb;begin
 perform private.material_audience(factory,audience);legacy:=private.planning_changes_before_materials(factory,audience);
 select coalesce(jsonb_agg(jsonb_build_object('request_id',e.id,'code',o.code,'material_operation',e.operation,'quantity',e.after_state->>'quantity','unit',e.after_state->>'unit','reserved',e.after_state->>'reserved','issued',e.after_state->>'issued','consumed',e.after_state->>'consumed','reason_note','','changed_by_name',coalesce(p.display_name,'System'),'changed_at',e.created_at,'prepared',false)order by e.created_at desc,e.id),'[]')into material from private.material_preparation_events e join public.production_orders o on o.factory_id=e.factory_id and o.id=e.item_id left join public.memberships p on p.factory_id=e.factory_id and p.user_id=e.actor where e.factory_id=factory and(e.operation in('REQUESTED','REACTIVATED','RELEASED')or audience='PRODUCTION'and e.operation in('RESERVE','ISSUE','RETURN','RELEASE'))and not exists(select 1 from private.material_preparation_acknowledgments a where a.factory_id=factory and a.event_id=e.id and a.user_id=auth.uid()and a.audience=planning_changes_read.audience);
 return jsonb_build_object('rows',legacy->'rows'||material);end$$;
alter function public.acknowledge_planning_change(uuid,uuid,text)set schema private;
alter function private.acknowledge_planning_change(uuid,uuid,text)rename to acknowledge_before_materials;
do $binding$begin execute replace(replace(pg_get_functiondef('private.acknowledge_before_materials(uuid,uuid,text)'::regprocedure),'acknowledge_planning_change.request_id','acknowledge_before_materials.request_id'),'acknowledge_planning_change.audience','acknowledge_before_materials.audience');end$binding$;
revoke all on function private.acknowledge_before_materials(uuid,uuid,text)from public,anon,authenticated,service_role;
create function public.acknowledge_planning_change(factory uuid,request_id uuid,audience text)returns jsonb language plpgsql security definer set search_path='' as $$declare n jsonb;begin perform private.material_audience(factory,audience);
 if exists(select 1 from private.material_preparation_events e where e.factory_id=factory and e.id=acknowledge_planning_change.request_id)then
 if exists(select 1 from private.material_preparation_acknowledgments a where a.factory_id=factory and a.event_id=request_id and a.user_id=auth.uid()and a.audience=acknowledge_planning_change.audience)then return jsonb_build_object('acknowledged',true);end if;
 n:=public.planning_changes_read(factory,audience);if not exists(select 1 from jsonb_array_elements(n->'rows')r where r->>'request_id'=request_id::text)then raise exception 'permission_denied'using errcode='42501';end if;
 insert into private.material_preparation_acknowledgments values(factory,request_id,auth.uid(),audience,clock_timestamp())on conflict do nothing;return jsonb_build_object('acknowledged',true);end if;
 return private.acknowledge_before_materials(factory,request_id,audience);end$$;
revoke all on function private.material_audience(uuid,text),public.production_material_work(uuid,text,uuid),public.planning_changes_read(uuid,text),public.acknowledge_planning_change(uuid,uuid,text)from public,anon,authenticated,service_role;
grant execute on function public.production_material_work(uuid,text,uuid),public.planning_changes_read(uuid,text),public.acknowledge_planning_change(uuid,uuid,text)to authenticated;

-- Planning already owns the structure lock. Reconciliation never acquires the outer
-- factory lock here, preserving the established factory -> structure lock order.
create function private.reconcile_material_item(f uuid,i uuid)returns integer language plpgsql set search_path='' as $$
declare o public.production_orders;requirements jsonb;x jsonb;m public.material_requests;p private.material_request_progress;key text;manual numeric;need numeric;label text;created integer:=0;warning text;lead_seconds numeric;
begin
 select *into o from public.production_orders where factory_id=f and id=i for update;if not found then return 0;end if;
 select coalesce((select seconds from private.production_material_policy where factory_id=f),21600)into lead_seconds;
 if o.status in('completed','cancelled')or(o.status='planned'and(o.start_time is null or o.start_time>clock_timestamp()+lead_seconds*interval '1 second'))then perform private.release_material_preparation(f,i);insert into private.material_preparation_jobs values(f,i,null,clock_timestamp())on conflict(factory_id,item_id)do update set warning=null,checked_at=excluded.checked_at;return 0;end if;
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
 end loop;return created;end$$;
create or replace function private.process_material_preparation(f uuid)returns jsonb language plpgsql set search_path='' as $$declare i uuid;n integer:=0;begin
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 for i in select o.id from public.production_orders o left join private.material_preparation_jobs j on j.factory_id=o.factory_id and j.item_id=o.id where o.factory_id=f and o.status='planned'and o.actual_start is null and o.start_time is not null order by j.checked_at nulls first,o.id limit 200 loop n:=n+private.reconcile_material_item(f,i);end loop;return jsonb_build_object('created',n);end$$;
create or replace function private.material_schedule_changed()returns trigger language plpgsql set search_path='' as $$begin
 if new.start_time is not distinct from old.start_time and new.line_id is not distinct from old.line_id and new.status is not distinct from old.status then return new;end if;perform private.reconcile_material_item(new.factory_id,new.id);return new;end$$;
-- A bound local worker invokes the private processor; no client scheduler grant.
revoke all on function private.reconcile_material_item(uuid,uuid),private.process_material_preparation(uuid),private.material_schedule_changed()from public,anon,authenticated,service_role;

alter function private.planning_issued_time_change_safe(uuid,uuid)rename to planning_issued_before_materials;
create function private.planning_issued_time_change_safe(f uuid,i uuid)returns boolean language sql stable security definer set search_path='' as $$
select private.planning_issued_before_materials(f,i)or(
 exists(select 1 from public.production_orders o where o.factory_id=f and o.id=i and o.status='planned'and o.actual_start is null and o.actual_finish is null and o.produced_quantity=0)
 and not exists(select 1 from public.production_entries where factory_id=f and order_id=i)
 and not private.output_work_held(f,i)and not private.output_work_retired(f,i)
 and exists(select 1 from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=f and m.production_item_id=i and p.issued>0)
 and not exists(select 1 from public.material_requests m left join private.material_request_progress p on p.factory_id=m.factory_id and p.request_id=m.id where m.factory_id=f and m.production_item_id=i and m.status in('ISSUED','RECEIVED')and(p.request_id is null or p.consumed<>0 or p.issued<=0
 or p.issued<>(select coalesce(sum(case e.operation when 'ISSUE'then(e.intent->'payload'->>'quantity')::numeric when 'RETURN'then-(e.intent->'payload'->>'quantity')::numeric else 0 end),0)from private.material_preparation_events e where e.factory_id=f and e.request_id=m.id)
 or(m.product_id is not null and p.issued<>(select coalesce(sum(c.quantity-c.consumed),0)from private.material_source_custody c where c.factory_id=f and c.request_id=m.id)))))$$;
alter function private.planning_change_state(uuid,uuid)rename to planning_state_before_materials;
create function private.planning_change_state(f uuid,i uuid)returns jsonb language plpgsql stable security definer set search_path='' as $$declare s jsonb;detail jsonb;begin
 s:=private.planning_state_before_materials(f,i);
 select jsonb_build_object('progress',coalesce(jsonb_agg(to_jsonb(p)order by p.request_id),'[]'),'policy',(select to_jsonb(t)from private.production_material_policy t where t.factory_id=f),'requirements',private.material_requirement_inputs(f,i))into detail from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=f and m.production_item_id=i;
 return s||jsonb_build_object('material_request_exists',exists(select 1 from public.material_requests m where m.factory_id=f and m.production_item_id=i and m.status not in('CANCELLED','REJECTED')),'material_progress',detail,'fingerprint',md5((s->>'fingerprint')||detail::text));end$$;
-- Requests existing at the committed change establish Warehouse involvement.
do $read$declare ddl text;begin ddl:=pg_get_functiondef('private.planning_changes_before_materials(uuid,text)'::regprocedure);ddl:=replace(ddl,'and c.result->>''exceptional''=''true''','');ddl:=replace(ddl,'c.result->>''prepared''=''true''','(c.result->>''prepared''=''true''or exists(select 1 from public.material_requests m where m.factory_id=c.factory_id and m.production_item_id=c.item_id and m.created_at<=r.changed_at))');execute ddl;end$read$;
create function private.material_line_custody_guard()returns trigger language plpgsql set search_path='' as $$begin
 if new.line_id is distinct from old.line_id and new.line_id is not null and exists(select 1 from private.material_request_progress p join public.material_requests m on m.factory_id=p.factory_id and m.id=p.request_id where p.factory_id=new.factory_id and m.production_item_id=new.id and(p.reserved>0 or p.issued>0))then raise exception 'planning_material_return_required'using errcode='22023';end if;return new;end$$;
create trigger material_line_custody_guard before update of line_id on public.production_orders for each row execute function private.material_line_custody_guard();
revoke all on function private.planning_issued_before_materials(uuid,uuid),private.planning_state_before_materials(uuid,uuid),private.planning_issued_time_change_safe(uuid,uuid),private.planning_change_state(uuid,uuid),private.material_line_custody_guard()from public,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.production_material_configuration(factory uuid, product uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$begin
 perform private.require_permission(factory,'orders','view');
 if product is not null and not exists(select 1 from public.products where factory_id=factory and id=product)then raise exception 'material_configuration_invalid'using errcode='22023';end if;
 return jsonb_build_object('hours',trim_scale(coalesce((select seconds from private.production_material_policy where factory_id=factory),21600)/3600)::text,'seconds',coalesce((select seconds from private.production_material_policy where factory_id=factory),21600)::text,'steps',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'product_id',s.product_id,'position',s.position,'name',w.name,'kind',s.kind)order by s.position),'[]')from public.production_routing_steps s left join public.work_centers w on w.factory_id=s.factory_id and w.id=s.work_center_id where s.factory_id=factory and(product is null or s.product_id=product)),'routes',(select coalesce(jsonb_agg(to_jsonb(r)order by r.product_id,r.scope),'[]')from private.production_input_routes r where r.factory_id=factory and(product is null or r.product_id=product)));
end$function$;
commit;
