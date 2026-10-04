-- Request-local supplier names and normalized permanent-supplier uniqueness.
-- Existing status ownership, request revisions, receipts and retry protection retained.
alter table public.purchase_requisitions add column supplier_text text not null default '' check(length(supplier_text)<=200), add constraint purchase_supplier_identity check(supplier_id is null or supplier_text='');
alter table public.purchase_request_events add column supplier_name text not null default '';
create unique index suppliers_normalized_name on public.suppliers(factory_id,(lower(btrim(name))));

CREATE OR REPLACE FUNCTION private.apply_supply_command(factory uuid, action text, payload jsonb, request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result uuid;old uuid;r public.purchase_requisitions;m public.material_requests;v jsonb;row_data jsonb;
 target uuid;mat uuid;prod uuid;lot uuid;u text;label text;q numeric;actor_name text;next_status text;reason text;category uuid;supplier uuid;item record;begin
 perform private.require_permission(factory,'factory','view');
 if jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>30000 then raise exception 'supply_invalid';end if;
 -- Authorization precedes retry reads as well as all writes.
 if action in ('purchase_stock','receive_purchase','receive_wip','acknowledge_good') then perform private.require_permission(factory,'warehouse','edit');
 elsif action='purchase_manual' then perform private.require_permission(factory,'purchasing','create');
 elsif action='purchase_change' then
  if payload->>'action' not in ('clarify','receive_direct','cancel_own') then perform private.require_permission(factory,'purchasing','edit');end if;
 elsif action='supplier_save' then perform private.require_permission(factory,'suppliers','edit');
 elsif action='material_request' then perform private.require_permission(factory,'orders','edit');
 elsif action='material_change' then
  if payload->>'action' in ('issue','reject','cancel') then perform private.require_permission(factory,'warehouse','issue');end if;
 else raise exception 'supply_invalid';end if;
 old:=private.fulfillment_retry(factory,request_id,'supply_'||action,payload);if old is not null then return old;end if;
 actor_name:=coalesce((select display_name from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved'),'');
 if action in ('purchase_stock','purchase_manual') then
  q:=(payload->>'quantity')::numeric;u:=btrim(payload->>'unit');
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') then raise exception 'supply_invalid';end if;
  if action='purchase_stock' then
   target:=(payload->>'item')::uuid;
   select value into row_data from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text and value->>'unit'=u;
   if row_data is null or row_data->>'supply_source' not in ('EXTERNAL','BOTH') then raise exception 'supply_invalid';end if;
   mat:=case when row_data->>'entity'='material' then target end;prod:=case when row_data->>'entity'='finished' then target end;
   select * into r from public.purchase_requisitions pr where pr.factory_id=factory and pr.unit=u and (pr.material_id=mat or pr.product_id=prod) and pr.status not in ('RECEIVED','REJECTED','CANCELLED');
   if found then result:=r.id;
   else
    if row_data->>'minimum_status'<>'AT_OR_BELOW_MIN' or (payload->>'projected')::numeric is distinct from (row_data->>'projected')::numeric
      or (row_data->>'already_requested')::boolean then raise exception 'warehouse_stock_changed';end if;
    insert into public.purchase_requisitions(factory_id,material_id,product_id,item_name,quantity,unit,details,notes,source_context,requested_by,requested_by_name,stock_context)
    values(factory,mat,prod,row_data->>'name',q,u,'Stock replenishment',coalesce(payload->>'notes',''),'Warehouse',auth.uid(),actor_name,row_data) returning id into result;
    perform private.supply_event(factory,result,'');
   end if;
  else
   if coalesce(length(btrim(payload->>'item_name')),0) not between 1 and 200 or coalesce(length(btrim(payload->>'details')),0) not between 1 and 4000
     or coalesce(length(u),0) not between 1 and 50 or coalesce(length(btrim(payload->>'source_context')),0) not between 1 and 120 then raise exception 'supply_invalid';end if;
   insert into public.purchase_requisitions(factory_id,item_name,quantity,unit,details,notes,source_context,requested_by,requested_by_name)
   values(factory,btrim(payload->>'item_name'),q,u,btrim(payload->>'details'),coalesce(payload->>'notes',''),btrim(payload->>'source_context'),auth.uid(),actor_name) returning id into result;
   perform private.supply_event(factory,result,'');
  end if;
 elsif action in ('purchase_change','receive_purchase') then
  select * into r from public.purchase_requisitions pr where pr.factory_id=factory and pr.id=(payload->>'id')::uuid for update;
  if not found then raise exception 'supply_invalid';end if;
  if r.revision is distinct from (payload->>'revision')::integer then raise exception 'supply_conflict';end if;
  if r.status in ('RECEIVED','REJECTED','CANCELLED') then raise exception 'supply_state';end if;
  result:=r.id;reason:=btrim(coalesce(payload->>'reason',''));next_status:=payload->>'action';
  if action='receive_purchase' then
   if r.status<>'READY_FOR_RECEIPT' or num_nonnulls(r.material_id,r.product_id)<>1 then raise exception 'supply_state';end if;
   -- The existing External Receipt command remains the only inventory receiving path.
   target:=public.receive_warehouse_stock(factory,coalesce(r.material_id,r.product_id),case when r.material_id is not null then 'material' else 'finished' end,r.unit,r.quantity,'external_receipt',r.code,reason,gen_random_uuid());
   update public.purchase_requisitions set receipt_movement_id=target,received_by=auth.uid(),received_at=clock_timestamp() where id=r.id;
   next_status:='RECEIVED';
  elsif next_status='receive_direct' then
   if r.requested_by<>auth.uid() or r.status<>'READY_FOR_RECEIPT' or num_nonnulls(r.material_id,r.product_id)<>0 then raise exception 'supply_state';end if;
   update public.purchase_requisitions set received_by=auth.uid(),received_at=clock_timestamp() where id=r.id;next_status:='RECEIVED';
  elsif next_status='clarify' then
   if r.requested_by<>auth.uid() or r.status<>'NEEDS_CLARIFICATION' or length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;
   next_status:='REQUESTED';
  elsif next_status='cancel_own' then
   if r.requested_by<>auth.uid() or r.status not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   if length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;next_status:='CANCELLED';
  elsif next_status='supplier' then
   if r.status not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   supplier:=nullif(payload->>'supplier_id','')::uuid;label:=btrim(coalesce(payload->>'supplier_text',''));
   if supplier is not null and label<>'' then raise exception 'supply_invalid';end if;
   if supplier is null then
    if length(label) not between 1 and 200 then raise exception 'supply_invalid';end if;
    select id into supplier from public.suppliers where factory_id=factory and lower(btrim(name))=lower(label);
   end if;
   if supplier is not null then
    if not exists(select 1 from public.suppliers where factory_id=factory and id=supplier and active) then raise exception 'supply_invalid';end if;
    label:='';
   end if;
   update public.purchase_requisitions set supplier_id=supplier,supplier_text=label where id=r.id;next_status:=r.status;
  else
   if next_status in ('NEEDS_CLARIFICATION','REJECTED','CANCELLED') and length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;
   if not ((next_status='UNDER_REVIEW' and r.status='REQUESTED') or (next_status='ORDERED' and r.status='UNDER_REVIEW' and (r.supplier_id is not null or r.supplier_text<>''))
    or (next_status='READY_FOR_RECEIPT' and r.status='ORDERED') or (next_status in ('NEEDS_CLARIFICATION','REJECTED') and r.status in ('REQUESTED','UNDER_REVIEW'))
    or next_status='CANCELLED') then raise exception 'supply_state';end if;
  end if;
  update public.purchase_requisitions set status=next_status,revision=revision+1,purchasing_note=case when reason<>'' then reason else purchasing_note end where id=r.id;
  perform private.supply_event(factory,r.id,reason);
 elsif action='supplier_save' then
  if coalesce(length(btrim(payload->>'name')),0) not between 1 and 200 or length(coalesce(payload->>'phone',''))>100 or length(coalesce(payload->>'email',''))>200 or length(coalesce(payload->>'notes',''))>4000 then raise exception 'supply_invalid';end if;
  result:=coalesce((payload->>'id')::uuid,gen_random_uuid());
  if payload->>'id' is not null then
   update public.suppliers set name=btrim(payload->>'name'),primary_contact=coalesce(payload->>'primary_contact',''),phone=coalesce(payload->>'phone',''),email=coalesce(payload->>'email',''),notes=coalesce(payload->>'notes',''),active=coalesce((payload->>'active')::boolean,true) where factory_id=factory and id=result;
   if not found then raise exception 'supply_invalid';end if;
  else insert into public.suppliers(id,factory_id,name,primary_contact,phone,email,notes,active) values(result,factory,btrim(payload->>'name'),coalesce(payload->>'primary_contact',''),coalesce(payload->>'phone',''),coalesce(payload->>'email',''),coalesce(payload->>'notes',''),coalesce((payload->>'active')::boolean,true)) on conflict (factory_id,(lower(btrim(name)))) do update set name=public.suppliers.name returning id into result;end if;
  if nullif(btrim(payload->>'category'),'') is not null then
   insert into public.supplier_categories(factory_id,name) values(factory,btrim(payload->>'category')) on conflict(factory_id,name) do update set name=excluded.name returning id into category;
   if payload->>'relationship'='PRIMARY' and exists(select 1 from public.supplier_category_links where factory_id=factory and category_id=category and supplier_id<>result and relationship='PRIMARY') then
    if coalesce((payload->>'replace_primary')::boolean,false) is not true then raise exception 'supply_conflict';end if;
    update public.supplier_category_links set relationship='ALTERNATIVE' where factory_id=factory and category_id=category and relationship='PRIMARY';
   end if;
   insert into public.supplier_category_links values(factory,result,category,coalesce(payload->>'relationship','ALTERNATIVE')) on conflict(factory_id,supplier_id,category_id) do update set relationship=excluded.relationship;
  end if;
 elsif action='material_request' then
  target:=(payload->>'item')::uuid;u:=payload->>'unit';q:=(payload->>'quantity')::numeric;
  if payload->>'item_type'='lot' then
   select o.unit,p.name into u,label from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id where l.factory_id=factory and l.id=target and l.warehouse_quantity>0;
   lot:=target;
  else
   select value into row_data from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text and value->>'unit'=u;
   if row_data->>'entity'='material' then mat:=target;else prod:=target;end if;label:=row_data->>'name';
  end if;
  if label is null or u is distinct from payload->>'unit' or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or length(coalesce(payload->>'note',''))>2000 then raise exception 'supply_invalid';end if;
  insert into public.material_requests(factory_id,material_id,product_id,lot_id,production_item_id,item_name,quantity,unit,note,requested_by,requested_by_name)
  values(factory,mat,prod,lot,(payload->>'production_item_id')::uuid,label,q,u,coalesce(payload->>'note',''),auth.uid(),actor_name) returning id into result;
 elsif action='material_change' then
  select * into m from public.material_requests mr where mr.factory_id=factory and mr.id=(payload->>'id')::uuid for update;
  if not found then raise exception 'supply_invalid';end if;
  if m.revision is distinct from (payload->>'revision')::integer then raise exception 'supply_conflict';end if;
  result:=m.id;reason:=btrim(coalesce(payload->>'reason',''));
  if payload->>'action'='receive' then
   if m.status<>'ISSUED' or m.requested_by<>auth.uid() then raise exception 'supply_state';end if;
   update public.material_requests set status='RECEIVED',received_by=auth.uid(),received_at=clock_timestamp(),revision=revision+1 where id=m.id;
  elsif payload->>'action' in ('reject','cancel') then
   if m.status<>'REQUESTED' then raise exception 'supply_state';end if;
   if length(reason) not between 1 and 2000 then raise exception 'supply_reason';end if;
   update public.material_requests set status=case when payload->>'action'='reject' then 'REJECTED' else 'CANCELLED' end,reason=reason,revision=revision+1 where id=m.id;
  elsif payload->>'action'='issue' then
   if m.status<>'REQUESTED' then raise exception 'supply_state';end if;target:=gen_random_uuid();
   if m.lot_id is not null then
    select * into item from public.unfinished_lots where factory_id=factory and id=m.lot_id for update;
    if item.warehouse_quantity<m.quantity then raise exception 'supply_insufficient';end if;
    update public.unfinished_lots set warehouse_quantity=warehouse_quantity-m.quantity where id=m.lot_id;
    insert into public.unfinished_movements(id,factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(target,factory,m.lot_id,item.source_entry_id,'warehouse_issue',0,-m.quantity,auth.uid());
   elsif m.material_id is not null then
    if not exists(select 1 from public.materials where factory_id=factory and id=m.material_id and unit=m.unit) then raise exception 'supply_invalid';end if;
    select coalesce(sum(quantity),0)-(select coalesce(sum(quantity),0) from public.inventory_reservations where factory_id=factory and material_id=m.material_id and released_at is null) into q from public.inventory_transactions where factory_id=factory and material_id=m.material_id;
    if q<m.quantity then raise exception 'supply_insufficient';end if;
    insert into public.inventory_transactions(id,factory_id,material_id,quantity,kind,unit,reference,note,created_by) values(target,factory,m.material_id,-m.quantity,'material_consumption',m.unit,m.id::text,'Production material issue',auth.uid());
   else
    select on_hand-reserved into q from public.finished_goods_balances where factory_id=factory and product_id=m.product_id and unit=m.unit for update;
    if coalesce(q,0)<m.quantity then raise exception 'supply_insufficient';end if;
    update public.finished_goods_balances set on_hand=on_hand-m.quantity where factory_id=factory and product_id=m.product_id and unit=m.unit;
    insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,external_reference,created_by) values(target,factory,m.product_id,m.unit,'material_issue',-m.quantity,'Production material issue',m.id::text,auth.uid());
   end if;
   update public.material_requests set status='ISSUED',issued_by=auth.uid(),issued_at=clock_timestamp(),movement_id=target,revision=revision+1 where id=m.id;
  else raise exception 'supply_invalid';end if;
 elsif action='receive_wip' then
  target:=(payload->>'lot')::uuid;q:=(payload->>'quantity')::numeric;
  select * into item from public.unfinished_lots where factory_id=factory and id=target for update;
  if not found or q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or q>item.quantity_available-item.warehouse_quantity then raise exception 'supply_insufficient';end if;
  update public.unfinished_lots set warehouse_quantity=warehouse_quantity+q where id=target;
  result:=gen_random_uuid();insert into public.unfinished_movements(id,factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by) values(result,factory,target,item.source_entry_id,'warehouse_receipt',0,q,auth.uid());
 elsif action='acknowledge_good' then
  target:=(payload->>'entry')::uuid;
  if not exists(select 1 from public.finished_goods_entry_receipts where factory_id=factory and entry_id=target and received_good>0) then raise exception 'supply_state';end if;
  insert into public.production_receipt_acknowledgments values(factory,target,auth.uid(),clock_timestamp()) on conflict do nothing;result:=target;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'supply_'||action,payload,result,clock_timestamp());return result;
end$function$
;

CREATE OR REPLACE FUNCTION public.supply_command(factory uuid, action text, payload jsonb, request_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare allowed text[];begin
 perform private.require_permission(factory,'factory','view');
 allowed:=case action
  when 'purchase_manual' then array['item_name','quantity','unit','details','notes','source_context']
  when 'purchase_stock' then array['item','quantity','unit','projected','notes']
  when 'purchase_inventory' then array['item','quantity','unit','details']
  when 'purchase_change' then array['id','revision','action','reason','supplier_id','supplier_text']
  when 'receive_purchase' then array['id','revision','reason']
  when 'supplier_save' then array['id','name','primary_contact','phone','email','notes','active','category','relationship','replace_primary']
  when 'material_request' then array['item','item_type','quantity','unit','note','production_item_id']
  when 'material_change' then array['id','revision','action','reason']
  when 'receive_wip' then array['lot','quantity'] when 'acknowledge_good' then array['entry'] end;
 if allowed is null or jsonb_typeof(payload) is distinct from 'object' or request_id is null or octet_length(payload::text)>30000 then raise exception 'supply_invalid';end if;
 if exists(select 1 from jsonb_object_keys(payload) k where not k=any(allowed)) then raise exception 'supply_invalid';end if;
 if action='supplier_save' and (length(coalesce(payload->>'primary_contact',''))>200 or length(coalesce(payload->>'category',''))>120) then raise exception 'supply_invalid';end if;
 if action='purchase_inventory' then return private.warehouse_inventory_purchase(factory,payload,request_id);end if;
 return private.apply_supply_command(factory,action,payload,request_id);
end$function$
;

CREATE OR REPLACE FUNCTION public.supply_page(factory uuid, mode text, page integer DEFAULT 1, filters jsonb DEFAULT '{}'::jsonb, selected uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$declare result jsonb;broad boolean;rows_data jsonb;total integer;details jsonb;begin
 perform private.require_permission(factory,'factory','view');
 if page is null or page not between 1 and 1000000 or jsonb_typeof(filters) is distinct from 'object' or octet_length(filters::text)>12000
  or exists(select 1 from jsonb_each(filters) k where k.key not in ('search','status','source_context','code','item_name','requested_by_name') or (k.key<>'status' and jsonb_typeof(k.value)<>'string') or (k.key='status' and jsonb_typeof(k.value)<>'array')) then raise exception 'supply_invalid';end if;
 if filters ? 'status' and exists(select 1 from jsonb_array_elements(filters->'status') x where jsonb_typeof(x)<>'string' or x#>>'{}' not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION','ORDERED','READY_FOR_RECEIPT','RECEIVED','REJECTED','CANCELLED')) then raise exception 'supply_invalid';end if;
 if mode in ('purchases','mine','stock_purchases') then
  broad:=mode='stock_purchases' or (mode='purchases' and private.has_permission(factory,'purchasing','view'));
  if mode='stock_purchases' then perform private.require_permission(factory,'warehouse','view');end if;
  if mode='purchases' and not broad then raise exception 'permission_denied' using errcode='42501';end if;
  with data as materialized(select r.*,coalesce((select name from public.suppliers where factory_id=factory and id=r.supplier_id),nullif(r.supplier_text,'')) supplier_name from public.purchase_requisitions r where r.factory_id=factory and (broad or r.requested_by=auth.uid())
   and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null or (r.source_context='Warehouse' and r.requested_by=auth.uid()))
   and (coalesce(filters->>'search','')='' or lower(r.item_name||' '||r.code||' '||r.requested_by_name||' '||r.source_context) like '%'||lower(filters->>'search')||'%')
   and (coalesce(jsonb_array_length(filters->'status'),0)=0 or filters->'status' @> jsonb_build_array(r.status))
   and (coalesce(filters->>'source_context','')='' or strpos(lower(r.source_context),lower(filters->>'source_context'))>0)
   and (coalesce(filters->>'code','')='' or strpos(lower(r.code),lower(filters->>'code'))>0)
   and (coalesce(filters->>'item_name','')='' or strpos(lower(r.item_name),lower(filters->>'item_name'))>0)
   and (coalesce(filters->>'requested_by_name','')='' or strpos(lower(r.requested_by_name),lower(filters->>'requested_by_name'))>0))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  if selected is not null then
   select to_jsonb(r)||jsonb_build_object('supplier_name',coalesce((select name from public.suppliers where factory_id=factory and id=r.supplier_id),nullif(r.supplier_text,'')),'history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.purchase_request_events e where e.factory_id=factory and e.request_id=r.id)) into details
   from public.purchase_requisitions r where r.factory_id=factory and r.id=selected and (broad or r.requested_by=auth.uid()) and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null or (r.source_context='Warehouse' and r.requested_by=auth.uid()));
  end if;
 elsif mode='suppliers' then
  if not private.has_permission(factory,'purchasing','view') and not private.has_permission(factory,'purchasing','edit') then perform private.require_permission(factory,'suppliers','edit');end if;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('categories',(select coalesce(jsonb_agg(jsonb_build_object('name',c.name,'relationship',l.relationship)),'[]') from public.supplier_category_links l join public.supplier_categories c on c.id=l.category_id where l.factory_id=factory and l.supplier_id=x.id))),'[]') into rows_data
  from (select * from public.suppliers where factory_id=factory and strpos(lower(name),lower(coalesce(filters->>'search','')))>0 order by name,id limit 50 offset (page-1)*50)x;
  select count(*) into total from public.suppliers where factory_id=factory and strpos(lower(name),lower(coalesce(filters->>'search','')))>0;
 elsif mode='materials' then
  if not private.has_permission(factory,'warehouse','view') then perform private.require_permission(factory,'orders','view');end if;
  with data as materialized(select * from public.material_requests where factory_id=factory and (private.has_permission(factory,'warehouse','view') or requested_by=auth.uid()))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
 elsif mode in ('catalogue','lots','outputs','formulas') then
  if not private.has_permission(factory,'warehouse','view') then perform private.require_permission(factory,'orders','view');end if;
  if mode='catalogue' then
   with data as materialized(select value r from private.warehouse_inventory_rows(factory) value where coalesce(filters->>'search','')='' or strpos(lower(concat_ws(' ',value->>'name',value->>'name_ar',value->>'code')),lower(filters->>'search'))>0)
   select (select coalesce(jsonb_agg(r),'[]') from(select r from data order by r->>'name',r->>'id' limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  elsif mode='lots' then
   with data as materialized(select l.*,p.id product_id,p.name,p.name_ar,e.unit,o.code item_code,o.request_id,
    (select code from public.production_requests where id=o.request_id) request_code,
    l.quantity_available-l.warehouse_quantity floor_quantity,
    (select coalesce(jsonb_agg(to_jsonb(m)||jsonb_build_object('actor_name',coalesce((select display_name from public.memberships where factory_id=factory and user_id=m.created_by),'')) order by m.created_at,m.id),'[]') from public.unfinished_movements m where m.factory_id=factory and m.lot_id=l.id) movements
    from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id
    where l.factory_id=factory and l.quantity_available>0 and (selected is null or p.id=selected))
   select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  elsif mode='outputs' then
   with data as materialized(select e.id,e.order_id,o.product_id,p.name,p.name_ar,o.code,e.unit,e.effective_good,e.created_at
    from public.production_entries e join public.production_orders o on o.id=e.order_id join public.products p on p.id=o.product_id
    where e.factory_id=factory and e.effective_good>0 and exists(select 1 from public.finished_goods_entry_receipts where factory_id=factory and entry_id=e.id and received_good>0)
     and not exists(select 1 from public.production_receipt_acknowledgments where factory_id=factory and entry_id=e.id))
   select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from(select * from data order by created_at,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  else
   perform private.require_permission(factory,'orders','view');
   select coalesce(jsonb_agg(to_jsonb(m)),'[]') into rows_data from (select * from public.materials where factory_id=factory and unit='kg' and inventory_kind='RAW_MATERIAL' order by name,id limit 500)m;
   total:=jsonb_array_length(rows_data);
   if selected is not null then select to_jsonb(b)||jsonb_build_object('components',(select jsonb_agg(to_jsonb(i)) from public.bom_items i where i.factory_id=factory and i.bom_id=b.id)) into details from public.bom_versions b where b.factory_id=factory and b.product_id=selected and b.output_unit='kg' order by version desc,created_at desc,id desc limit 1;end if;
  end if;
 else raise exception 'supply_invalid';end if;
 return jsonb_build_object('rows',rows_data,'total',total,'selected',details);
end$function$
;

CREATE OR REPLACE FUNCTION private.supply_event(f uuid, r uuid, n text)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
 insert into public.purchase_request_events(factory_id,request_id,status,note,supplier_id,actor_id,actor_name,supplier_name)
 select f,id,status,coalesce(n,''),supplier_id,auth.uid(),coalesce((select display_name from public.memberships where factory_id=f and user_id=auth.uid()),''),coalesce((select name from public.suppliers where factory_id=f and id=supplier_id),supplier_text)
 from public.purchase_requisitions where factory_id=f and id=r;
$function$
;
