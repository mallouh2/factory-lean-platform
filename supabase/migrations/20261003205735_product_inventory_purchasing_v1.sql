-- Product identity, formulas, procurement and explicit material flow. No historical inference.
alter table public.products add column product_kind text not null default 'FINISHED_PRODUCT'
 check(product_kind in ('FINISHED_PRODUCT','MANUFACTURED_INTERMEDIATE')),
 add column formula_product_id uuid,
 add column unit_weight_kg numeric check(unit_weight_kg>0 and unit_weight_kg::text not in ('NaN','Infinity','-Infinity')),
 add foreign key(factory_id,formula_product_id) references public.products(factory_id,id);
alter table public.bom_versions add column output_unit text, add column created_by uuid references auth.users;
alter table public.materials drop constraint materials_inventory_kind_check;
alter table public.materials add constraint materials_inventory_kind_check
 check(inventory_kind in ('RAW_MATERIAL','ACCESSORY','PACKAGING','SEMI_FINISHED'));
-- Legacy SEMI_FINISHED identities remain exactly as recorded; new creation excludes them.
alter table public.unfinished_lots add column warehouse_quantity numeric not null default 0
 check(warehouse_quantity>=0 and warehouse_quantity<=quantity_available);
alter table public.unfinished_movements add column location_delta numeric not null default 0;
alter table public.unfinished_movements drop constraint unfinished_movements_kind_check;
alter table public.unfinished_movements add constraint unfinished_movements_kind_check
 check(kind in ('created','consumed','corrected','warehouse_receipt','warehouse_issue'));
alter table public.finished_goods_movements drop constraint finished_goods_movements_kind_check;
alter table public.finished_goods_movements add constraint finished_goods_movements_kind_check
 check(kind in ('production_receipt','production_correction','reservation','release','dispatch','adjustment','opening_balance','external_receipt','material_issue'));

insert into public.permissions(module,action) values ('purchasing','view'),('purchasing','create'),
 ('purchasing','edit'),('suppliers','edit') on conflict do nothing;
alter table public.suppliers add column primary_contact text not null default '',
 add column phone text not null default '', add column email text not null default '',
 add column notes text not null default '', add column active boolean not null default true;
create table public.supplier_categories(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 name text not null check(length(btrim(name)) between 1 and 120),unique(factory_id,id),unique(factory_id,name));
create table public.supplier_category_links(
 factory_id uuid not null,supplier_id uuid not null,category_id uuid not null,
 relationship text not null check(relationship in ('PRIMARY','ALTERNATIVE')),
 primary key(factory_id,supplier_id,category_id),
 foreign key(factory_id,supplier_id) references public.suppliers(factory_id,id),
 foreign key(factory_id,category_id) references public.supplier_categories(factory_id,id));
create unique index one_primary_supplier on public.supplier_category_links(factory_id,category_id) where relationship='PRIMARY';
create sequence private.purchase_reference_seq;
-- Extend the existing request foundation; formal PO/goods_receipts tables remain unused.
alter table public.purchase_requisitions add column code text not null default ('PR-'||lpad(nextval('private.purchase_reference_seq')::text,7,'0')),
 add column product_id uuid, add column item_name text not null,
 add column unit text not null, add column details text not null,
 add column notes text not null default '', add column source_context text not null,
 add column requested_by uuid not null references auth.users, add column requested_by_name text not null,
 add column status text not null default 'REQUESTED' check(status in ('REQUESTED','UNDER_REVIEW','ORDERED','READY_FOR_RECEIPT','RECEIVED','NEEDS_CLARIFICATION','REJECTED','CANCELLED')),
 add column supplier_id uuid, add column revision integer not null default 1,
 add column purchasing_note text not null default '', add column stock_context jsonb,
 add column received_by uuid references auth.users, add column received_at timestamptz, add column receipt_movement_id uuid,
 add foreign key(factory_id,product_id) references public.products(factory_id,id),
 add foreign key(factory_id,supplier_id) references public.suppliers(factory_id,id),
 add check(material_id is null or product_id is null),
 add check(length(btrim(item_name)) between 1 and 200 and length(btrim(unit)) between 1 and 50 and length(btrim(details)) between 1 and 4000),
 add check(length(notes)<=4000 and length(source_context) between 1 and 120),
 add check(quantity is not null and quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity'));
create index purchase_factory_time on public.purchase_requisitions(factory_id,created_at desc,id);
create index purchase_requester on public.purchase_requisitions(factory_id,requested_by,created_at desc);
create unique index active_material_purchase on public.purchase_requisitions(factory_id,material_id,unit)
 where material_id is not null and status not in ('RECEIVED','REJECTED','CANCELLED');
create unique index active_product_purchase on public.purchase_requisitions(factory_id,product_id,unit)
 where product_id is not null and status not in ('RECEIVED','REJECTED','CANCELLED');
create table public.purchase_request_events(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null,request_id uuid not null,
 status text not null,note text not null default '',supplier_id uuid,
 actor_id uuid not null references auth.users,actor_name text not null,created_at timestamptz not null default clock_timestamp(),
 foreign key(factory_id,request_id) references public.purchase_requisitions(factory_id,id),
 foreign key(factory_id,supplier_id) references public.suppliers(factory_id,id));
create index purchase_events_request on public.purchase_request_events(factory_id,request_id,created_at,id);
create table public.material_requests(
 id uuid primary key default gen_random_uuid(),factory_id uuid not null references public.factories,
 material_id uuid,product_id uuid,lot_id uuid,production_item_id uuid,
 item_name text not null,quantity numeric not null check(quantity>0 and quantity::text not in ('NaN','Infinity','-Infinity')),
 unit text not null,note text not null default '',
 requested_by uuid not null references auth.users,requested_by_name text not null,
 created_at timestamptz not null default clock_timestamp(),
 status text not null default 'REQUESTED' check(status in ('REQUESTED','ISSUED','RECEIVED','REJECTED','CANCELLED')),
 issued_by uuid references auth.users,issued_at timestamptz,movement_id uuid,
 received_by uuid references auth.users,received_at timestamptz,reason text not null default '',revision integer not null default 1,
 unique(factory_id,id),check(num_nonnulls(material_id,product_id,lot_id)=1),
 foreign key(factory_id,material_id) references public.materials(factory_id,id),
 foreign key(factory_id,product_id) references public.products(factory_id,id),
 foreign key(factory_id,lot_id) references public.unfinished_lots(factory_id,id),
 foreign key(factory_id,production_item_id) references public.production_orders(factory_id,id));
create index material_requests_factory on public.material_requests(factory_id,status,created_at desc);
create table public.production_receipt_acknowledgments(
 factory_id uuid not null,entry_id uuid not null,received_by uuid not null references auth.users,
 received_at timestamptz not null default clock_timestamp(),primary key(factory_id,entry_id),
 foreign key(factory_id,entry_id) references public.production_entries(factory_id,id));
-- Readers are scoped RPCs; direct mutations and generic legacy policies cannot bypass transitions.
do $$declare tab text;pol record;begin
 foreach tab in array array['suppliers','supplier_categories','supplier_category_links','purchase_requisitions','purchase_request_events','material_requests','production_receipt_acknowledgments','bom_versions','bom_items'] loop
  execute format('alter table public.%I enable row level security',tab);
  execute format('revoke all on public.%I from anon,authenticated',tab);
  for pol in select policyname from pg_policies where schemaname='public' and tablename=tab loop execute format('drop policy %I on public.%I',pol.policyname,tab);end loop;
 end loop;
 foreach tab in array array['suppliers','supplier_categories','supplier_category_links','purchase_requisitions','material_requests','production_receipt_acknowledgments'] loop
  execute format('create trigger audit_supply after insert or update or delete on public.%I for each row execute function private.audit_change()',tab);
 end loop;
end$$;

create function private.supply_event(f uuid,r uuid,n text) returns void language sql security definer set search_path='' as $$
 insert into public.purchase_request_events(factory_id,request_id,status,note,supplier_id,actor_id,actor_name)
 select f,id,status,coalesce(n,''),supplier_id,auth.uid(),coalesce((select display_name from public.memberships where factory_id=f and user_id=auth.uid()),'')
 from public.purchase_requisitions where factory_id=f and id=r;
$$;
create function public.supply_command(factory uuid,action text,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
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
   if r.requested_by<>auth.uid() or r.status not in ('REQUESTED','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   if length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;next_status:='CANCELLED';
  elsif next_status='supplier' then
   if r.status not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION') then raise exception 'supply_state';end if;
   supplier:=(payload->>'supplier_id')::uuid;
   if not exists(select 1 from public.suppliers where factory_id=factory and id=supplier and active) then raise exception 'supply_invalid';end if;
   update public.purchase_requisitions set supplier_id=supplier where id=r.id;next_status:=r.status;
  else
   if next_status in ('NEEDS_CLARIFICATION','REJECTED','CANCELLED') and length(reason) not between 1 and 4000 then raise exception 'supply_reason';end if;
   if not ((next_status='UNDER_REVIEW' and r.status='REQUESTED') or (next_status='ORDERED' and r.status='UNDER_REVIEW' and r.supplier_id is not null)
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
  else insert into public.suppliers(id,factory_id,name,primary_contact,phone,email,notes,active) values(result,factory,btrim(payload->>'name'),coalesce(payload->>'primary_contact',''),coalesce(payload->>'phone',''),coalesce(payload->>'email',''),coalesce(payload->>'notes',''),coalesce((payload->>'active')::boolean,true));end if;
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
end$$;
revoke all on function private.supply_event(uuid,uuid,text),public.supply_command(uuid,text,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.supply_command(uuid,text,jsonb,uuid) to authenticated;

-- Explicit kg production support uses the same typed rate, plan, recording and FG guards.
CREATE OR REPLACE FUNCTION private.save_record(f uuid, resource text, record_id uuid, p jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  table_name text; perm text; allowed text[]; k text; new_category uuid;
  columns_sql text:=''; values_sql text:=''; update_sql text:='';
  result_id uuid; action text; previous_order public.production_orders%rowtype;
  product_changed boolean; quantity_changed boolean;
begin
  action:=case when record_id is null then 'create' else 'edit' end;
  perm:=case when resource='products' then 'orders'
    when resource='work_center_categories' then 'centers' else resource end;
  perform private.require_permission(f,perm,action);
  if coalesce((p->>'archived')::boolean,false) then
    perform private.require_permission(f,perm,'delete');
  end if;
  case resource
    when 'factory' then table_name:='areas';allowed:=array['name','name_ar','archived'];
    when 'lines' then table_name:='production_lines';allowed:=array['name','name_ar','code','area_id','archived'];
    when 'centers' then table_name:='work_centers';allowed:=array['name','name_ar','code','type','category_id','parent_id','area_id','line_id','order_id','operator_id','description','notes','production_speed','default_cycle_time','current_cycle_time','planned_capacity','position','archived','start_time','expected_finish'];
    when 'work_center_categories' then table_name:='work_center_categories';allowed:=array['name','name_ar','icon_key','archived'];
    when 'products' then table_name:='products';allowed:=array['name','name_ar','code','unit','category','diameter','length','color','weight','standard_rate','stage'];
    when 'orders' then table_name:='production_orders';allowed:=array['code','product_id','line_id','status','target_quantity','start_time','expected_finish'];
    when 'downtime' then table_name:='downtime_reasons';allowed:=array['name','name_ar','parent_id','requires_description'];
    when 'roles' then table_name:='roles';allowed:=array['name','name_ar'];
    else raise exception 'invalid_resource';
  end case;
  if jsonb_typeof(p)<>'object' or p='{}'::jsonb then raise exception 'invalid_input'; end if;
  if resource='products' and record_id is null and coalesce(p->>'stage','finished')<>'finished' then raise exception 'supply_invalid';end if;
  if resource='centers' and p ? 'category_id' then
    if p->>'category_id' is null or not exists(
      select 1 from public.work_center_categories c
      where c.factory_id=f and c.id=(p->>'category_id')::uuid and c.archived=false
    ) then raise exception 'invalid_category'; end if;
    new_category:=(p->>'category_id')::uuid;
    if record_id is not null and new_category is distinct from (
      select category_id from public.work_centers where id=record_id and factory_id=f
    ) then
      if exists(
        select 1 from public.work_center_alternatives r
        where r.factory_id=f and record_id in (r.work_center_id,r.alternative_id)
          and exists(
            select 1 from public.work_centers other
            where other.id=case when r.work_center_id=record_id
              then r.alternative_id else r.work_center_id end
              and other.category_id is distinct from new_category
          )
      ) then raise exception 'category_alternative_conflict'; end if;
    end if;
  end if;
  if resource='work_center_categories' and record_id is not null
    and coalesce((p->>'archived')::boolean,false) then
    if exists(select 1 from public.work_centers w
      where w.category_id=record_id and w.factory_id=f and w.archived=false)
    then raise exception 'category_in_use'; end if;
  end if;

  if resource='orders' then
    if record_id is null then
      if nullif(p->>'line_id','') is not null
        or nullif(p->>'start_time','') is not null
        or nullif(p->>'expected_finish','') is not null
      then raise exception 'planning_use_plan_command'; end if;
    else
      select * into previous_order from public.production_orders
        where factory_id=f and id=record_id for update;
      if not found then raise exception 'not_found'; end if;
      if (p ? 'line_id' and (p->>'line_id')::uuid is distinct from previous_order.line_id)
        or (p ? 'start_time' and (p->>'start_time')::timestamptz is distinct from previous_order.start_time)
        or (p ? 'expected_finish' and (p->>'expected_finish')::timestamptz is distinct from previous_order.expected_finish)
      then raise exception 'planning_use_plan_command'; end if;

      product_changed:=p ? 'product_id'
        and (p->>'product_id')::uuid is distinct from previous_order.product_id;
      quantity_changed:=p ? 'target_quantity'
        and (p->>'target_quantity')::numeric is distinct from previous_order.target_quantity;
      if (product_changed or quantity_changed) and (
        previous_order.line_id is not null or previous_order.start_time is not null
        or previous_order.expected_finish is not null
        or previous_order.planning_ever_scheduled
        or previous_order.planning_locked_at is not null
        or previous_order.status<>'planned' or previous_order.produced_quantity>0
        or coalesce(p->>'status',previous_order.status)<>'planned'
      ) then raise exception 'planning_use_plan_command'; end if;

      -- A cancelled/completed item retains its stored times. Re-enabling it
      -- through a generic status edit could create a new overlap.
      if p ? 'status' and previous_order.status not in ('planned','active')
        and p->>'status' in ('planned','active')
        and (previous_order.line_id is not null or previous_order.start_time is not null
          or previous_order.expected_finish is not null)
      then raise exception 'planning_use_plan_command'; end if;
    end if;
  end if;

  for k in select jsonb_object_keys(p) loop
    if not k=any(allowed) then raise exception 'invalid_field'; end if;
    if columns_sql<>'' then
      columns_sql:=columns_sql||',';values_sql:=values_sql||',';update_sql:=update_sql||',';
    end if;
    columns_sql:=columns_sql||format('%I',k);
    values_sql:=values_sql||format('v.%I',k);
    update_sql:=update_sql||format('%I=v.%I',k,k);
  end loop;
  if record_id is null then
    execute format('insert into public.%I(factory_id,%s) select $1,%s from jsonb_populate_record(null::public.%I,$2) v returning id',table_name,columns_sql,values_sql,table_name)
      into result_id using f,p;
  else
    execute format('update public.%I t set %s from jsonb_populate_record(null::public.%I,$2) v where t.factory_id=$1 and t.id=$3 returning t.id',table_name,update_sql,table_name)
      into result_id using f,p,record_id;
  end if;
  if result_id is null then raise exception 'not_found'; end if;
  return result_id;
end;
$function$;

create or replace function public.create_warehouse_material(factory uuid,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$declare result uuid;begin
 perform private.require_permission(factory,'warehouse','edit');result:=private.fulfillment_retry(factory,request_id,'material',payload);if result is not null then return result;end if;
 if jsonb_typeof(payload) is distinct from 'object' or exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','name_ar','code','unit','inventory_kind'))
 or coalesce(length(btrim(payload->>'name')),0) not between 1 and 200 or coalesce(length(btrim(payload->>'code')),0) not between 1 and 100
 or coalesce(payload->>'unit','') not in ('kg','meter','piece') or coalesce(payload->>'inventory_kind','RAW_MATERIAL') not in ('RAW_MATERIAL','ACCESSORY','PACKAGING') then raise exception 'fulfillment_invalid';end if;
 insert into public.materials(factory_id,name,name_ar,code,unit,inventory_kind) values(factory,btrim(payload->>'name'),coalesce(payload->>'name_ar',''),btrim(payload->>'code'),payload->>'unit',coalesce(payload->>'inventory_kind','RAW_MATERIAL')) returning id into result;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'material',payload,result,clock_timestamp());return result;
end$$;

create function public.define_manufactured_product(factory uuid,product uuid,payload jsonb,components jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$declare result uuid;previous uuid;master jsonb;kind text;u text;formula uuid;bom uuid;v integer;part jsonb;amount numeric;seen uuid[]:='{}';mat uuid;begin
 perform private.require_permission(factory,'orders',case when product is null then 'create' else 'edit' end);
 master:=jsonb_build_object('product',product,'payload',payload,'components',components);
 previous:=private.fulfillment_retry(factory,request_id,'product_definition',master);if previous is not null then return previous;end if;
 if jsonb_typeof(payload) is distinct from 'object' or exists(select 1 from jsonb_object_keys(payload) k where k not in ('name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate','stage','product_kind','stock_unit','formula_product_id','unit_weight_kg')) then raise exception 'supply_invalid';end if;
 kind:=coalesce(payload->>'product_kind','FINISHED_PRODUCT');u:=payload->>'stock_unit';formula:=(payload->>'formula_product_id')::uuid;
 if kind not in ('FINISHED_PRODUCT','MANUFACTURED_INTERMEDIATE') or (product is null and coalesce(payload->>'stage','finished')<>'finished')
  or (kind='MANUFACTURED_INTERMEDIATE' and u is distinct from 'kg') then raise exception 'supply_invalid';end if;
 if formula is not null and (formula=product or not exists(select 1 from public.products where factory_id=factory and id=formula and product_kind='MANUFACTURED_INTERMEDIATE' and stock_unit='kg')
  or (payload->>'unit_weight_kg')::numeric is null or u is null) then raise exception 'supply_invalid';end if;
 result:=private.save_record(factory,'products',product,payload-array['product_kind','stock_unit','formula_product_id','unit_weight_kg']);
 update public.products set product_kind=kind,stock_unit=u,formula_product_id=formula,unit_weight_kg=(payload->>'unit_weight_kg')::numeric where id=result and factory_id=factory;
 if components is not null then
  if kind<>'MANUFACTURED_INTERMEDIATE' or formula is not null or jsonb_typeof(components) is distinct from 'array' or jsonb_array_length(components) not between 1 and 100 then raise exception 'supply_invalid';end if;
  select coalesce(max(version),0)+1 into v from public.bom_versions where factory_id=factory and product_id=result;
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by) values(factory,result,v,1,'kg',auth.uid()) returning id into bom;
  for part in select value from jsonb_array_elements(components) loop
   mat:=(part->>'material_id')::uuid;amount:=(part->>'quantity')::numeric;
   if mat=any(seen) or amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') or part->>'unit' is distinct from 'kg'
    or not exists(select 1 from public.materials where factory_id=factory and id=mat and unit='kg' and inventory_kind='RAW_MATERIAL') then raise exception 'supply_invalid';end if;
   seen:=array_append(seen,mat);insert into public.bom_items(factory_id,bom_id,material_id,quantity,unit) values(factory,bom,mat,amount,'kg');
  end loop;
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'product_definition',master,result,clock_timestamp());return result;
end$$;
revoke all on function public.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.define_manufactured_product(uuid,uuid,jsonb,jsonb,uuid) to authenticated;

create function public.product_requirements(factory uuid,product uuid,quantity numeric,unit text) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare p public.products;compound uuid;b public.bom_versions;amount numeric;begin
 perform private.require_permission(factory,'orders','view');
 select * into p from public.products where factory_id=factory and id=product;
 if not found or quantity is null or quantity<=0 or quantity::text in ('NaN','Infinity','-Infinity') or unit is distinct from p.stock_unit then raise exception 'supply_invalid';end if;
 compound:=case when p.product_kind='MANUFACTURED_INTERMEDIATE' then p.id else p.formula_product_id end;
 amount:=case when p.product_kind='MANUFACTURED_INTERMEDIATE' and unit='kg' then quantity else quantity*p.unit_weight_kg end;
 select * into b from public.bom_versions where factory_id=factory and product_id=compound and output_unit='kg' order by version desc,created_at desc,id desc limit 1;
 return jsonb_build_object('theoretical',true,'compound_id',compound,'compound_quantity_kg',amount,'formula_version',b.version,
 'raw_materials',case when b.id is null or amount is null then null else (select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'name',m.name,'name_ar',m.name_ar,'unit',i.unit,'quantity',amount*i.quantity/b.batch_quantity)),'[]') from public.bom_items i join public.materials m on m.id=i.material_id where i.factory_id=factory and i.bom_id=b.id) end);
end$$;
revoke all on function public.product_requirements(uuid,uuid,numeric,text) from public,anon,authenticated;
grant execute on function public.product_requirements(uuid,uuid,numeric,text) to authenticated;

create function private.purchase_incoming(f uuid,item uuid,u text) returns numeric language sql stable security definer set search_path='' as $$
 select coalesce(sum(quantity),0) from public.purchase_requisitions where factory_id=f and (product_id=item or material_id=item) and unit=u and status in ('ORDERED','READY_FOR_RECEIPT');
$$;

create or replace function private.warehouse_inventory_rows(f uuid) returns setof jsonb
language sql stable security definer set search_path='' as $$
 with all_projection as materialized(select * from private.finished_inventory_projection(f)),
 unit_keys as (select product_id,unit from all_projection where unit is not null union select o.product_id,e.unit from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and l.quantity_available>0),
 product_units as (select p.id,coalesce(p.stock_unit,case when count(distinct x.unit)=1 then min(x.unit) end) unit
  from public.products p left join unit_keys x on x.product_id=p.id where p.factory_id=f and p.stage='finished' group by p.id),
 base as (
 select p.id,'finished'::text entity,p.name,p.name_ar,p.code,case when p.product_kind='MANUFACTURED_INTERMEDIATE' then 'MANUFACTURED_INTERMEDIATE' else 'FINISHED_GOOD' end item_type,p.supply_source,k.unit,
 coalesce(x.on_hand,0) on_hand,coalesce(x.reserved,0) reserved,coalesce(x.on_hand-x.reserved,0) available,
 coalesce(x.incoming,0)-coalesce((select sum(o.remaining_quantity) from public.production_orders o where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status='active' and o.actual_start is not null and o.actual_finish is null),0)+private.purchase_incoming(f,p.id,k.unit) incoming,
 coalesce(x.projected,0)+private.purchase_incoming(f,p.id,k.unit) projected,case when k.unit=p.stock_unit then p.minimum_stock end minimum_stock,case when k.unit=p.stock_unit then p.maximum_stock end maximum_stock,
 coalesce((select sum(l.warehouse_quantity) from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and o.product_id=p.id and e.unit=k.unit),0) semi_finished,
 coalesce((select sum(o.remaining_quantity) from public.production_orders o where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status='active' and o.actual_start is not null and o.actual_finish is null),0) in_production,
 exists(select 1 from public.production_orders o join public.production_requests r on r.id=o.request_id where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status in ('planned','active') and r.request_type='STOCK_REPLENISHMENT') already_requested,
 exists(select 1 from public.purchase_requisitions pr where pr.factory_id=f and pr.product_id=p.id and pr.unit=k.unit and pr.status not in ('RECEIVED','REJECTED','CANCELLED')) purchase_requested,
 (select coalesce(jsonb_agg(coalesce(to_jsonb(z),'{}'::jsonb)||jsonb_build_object('unit',uk.unit,'semi_finished',coalesce((select sum(l.warehouse_quantity) from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and o.product_id=p.id and e.unit=uk.unit),0))),'[]') from unit_keys uk left join all_projection z on z.product_id=uk.product_id and z.unit=uk.unit where uk.product_id=p.id) unit_breakdown
 from public.products p join product_units k on k.id=p.id left join all_projection x on x.product_id=p.id and x.unit=k.unit where p.factory_id=f and p.stage='finished'
 union all
 select m.id,'material',m.name,m.name_ar,m.code,m.inventory_kind,'EXTERNAL',m.unit,
 coalesce((select sum(quantity) from public.inventory_transactions where factory_id=f and material_id=m.id),0),
 coalesce((select sum(quantity) from public.inventory_reservations where factory_id=f and material_id=m.id and released_at is null),0),
 coalesce((select sum(quantity) from public.inventory_transactions where factory_id=f and material_id=m.id),0)-coalesce((select sum(quantity) from public.inventory_reservations where factory_id=f and material_id=m.id and released_at is null),0),
 private.purchase_incoming(f,m.id,m.unit),
 coalesce((select sum(quantity) from public.inventory_transactions where factory_id=f and material_id=m.id),0)-coalesce((select sum(quantity) from public.inventory_reservations where factory_id=f and material_id=m.id and released_at is null),0)+private.purchase_incoming(f,m.id,m.unit),
 m.minimum_stock,m.maximum_stock,null::numeric,null::numeric,false,
 exists(select 1 from public.purchase_requisitions pr where pr.factory_id=f and pr.material_id=m.id and pr.status not in ('RECEIVED','REJECTED','CANCELLED')),'[]'::jsonb
 from public.materials m where m.factory_id=f
 ),detected as (select b.*,case when minimum_stock is null or unit is null then 'NOT_CONFIGURED' when projected<=minimum_stock then 'AT_OR_BELOW_MIN' else 'ABOVE_MIN' end minimum_status,
 case when maximum_stock is not null then maximum_stock-projected end suggested_quantity from base b)
 select to_jsonb(d)||jsonb_build_object('row_key',entity||':'||id,'external_chosen',false,
 'replenishment_status',case when purchase_requested then 'PURCHASE_REQUESTED' when already_requested then 'ALREADY_REQUESTED'
 when minimum_status='AT_OR_BELOW_MIN' then case supply_source when 'EXTERNAL' then 'EXTERNAL_REQUIRED' when 'BOTH' then 'SOURCING_REQUIRED' else 'PRODUCTION_REQUIRED' end
 when incoming>0 then 'INCOMING' else 'OK' end,
 'can_produce',entity='finished' and unit is not null and minimum_status='AT_OR_BELOW_MIN' and not already_requested and not purchase_requested and supply_source in ('MANUFACTURED','BOTH') and (suggested_quantity is null or suggested_quantity>0),
 'can_purchase',unit is not null and minimum_status='AT_OR_BELOW_MIN' and not already_requested and not purchase_requested and supply_source in ('EXTERNAL','BOTH')) from detected d;
$$;

create function public.supply_page(factory uuid,mode text,page integer default 1,filters jsonb default '{}',selected uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare result jsonb;broad boolean;rows_data jsonb;total integer;details jsonb;begin
 perform private.require_permission(factory,'factory','view');
 if page is null or page not between 1 and 1000000 or jsonb_typeof(filters) is distinct from 'object' or octet_length(filters::text)>12000
  or exists(select 1 from jsonb_each(filters) k where k.key not in ('search','status','source_context','code','item_name','requested_by_name') or (k.key<>'status' and jsonb_typeof(k.value)<>'string') or (k.key='status' and jsonb_typeof(k.value)<>'array')) then raise exception 'supply_invalid';end if;
 if filters ? 'status' and exists(select 1 from jsonb_array_elements(filters->'status') x where jsonb_typeof(x)<>'string' or x#>>'{}' not in ('REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION','ORDERED','READY_FOR_RECEIPT','RECEIVED','REJECTED','CANCELLED')) then raise exception 'supply_invalid';end if;
 if mode in ('purchases','mine','stock_purchases') then
  broad:=mode='stock_purchases' or (mode='purchases' and private.has_permission(factory,'purchasing','view'));
  if mode='stock_purchases' then perform private.require_permission(factory,'warehouse','view');end if;
  if mode='purchases' and not broad then raise exception 'permission_denied' using errcode='42501';end if;
  with data as materialized(select r.*,(select name from public.suppliers where factory_id=factory and id=r.supplier_id) supplier_name from public.purchase_requisitions r where r.factory_id=factory and (broad or r.requested_by=auth.uid())
   and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null)
   and (coalesce(filters->>'search','')='' or lower(r.item_name||' '||r.code||' '||r.requested_by_name||' '||r.source_context) like '%'||lower(filters->>'search')||'%')
   and (coalesce(jsonb_array_length(filters->'status'),0)=0 or filters->'status' @> jsonb_build_array(r.status))
   and (coalesce(filters->>'source_context','')='' or strpos(lower(r.source_context),lower(filters->>'source_context'))>0)
   and (coalesce(filters->>'code','')='' or strpos(lower(r.code),lower(filters->>'code'))>0)
   and (coalesce(filters->>'item_name','')='' or strpos(lower(r.item_name),lower(filters->>'item_name'))>0)
   and (coalesce(filters->>'requested_by_name','')='' or strpos(lower(r.requested_by_name),lower(filters->>'requested_by_name'))>0))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  if selected is not null then
   select to_jsonb(r)||jsonb_build_object('history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.purchase_request_events e where e.factory_id=factory and e.request_id=r.id)) into details
   from public.purchase_requisitions r where r.factory_id=factory and r.id=selected and (broad or r.requested_by=auth.uid()) and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null);
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
   with data as materialized(select value r from private.warehouse_inventory_rows(factory) value where coalesce(filters->>'search','')='' or lower(value->>'name') like '%'||lower(filters->>'search')||'%')
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
end$$;
revoke all on function private.purchase_incoming(uuid,uuid,text),public.supply_page(uuid,text,integer,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.supply_page(uuid,text,integer,jsonb,uuid) to authenticated;
create or replace function private.warehouse_filter_matches(row_data jsonb,filters jsonb) returns boolean
language plpgsql immutable set search_path='' as $$
declare k text;v jsonb;n numeric;op text;a numeric;b numeric;matched boolean:=true;begin
 if jsonb_typeof(filters) is distinct from 'object' or octet_length(filters::text)>12000 then raise exception 'fulfillment_invalid';end if;
 for k,v in select * from jsonb_each(filters) loop
 if k in ('name','code') then
  if jsonb_typeof(v)<>'string' or length(v#>>'{}')>200 then raise exception 'fulfillment_invalid';end if;
  if strpos(lower(coalesce(row_data->>k,'')||case when k='name' then ' '||coalesce(row_data->>'name_ar','') else '' end),lower(v#>>'{}'))=0 then matched:=false;end if;
 elsif k in ('item_type','supply_source','unit','minimum_status','replenishment_status') then
  if jsonb_typeof(v)<>'array' or jsonb_array_length(v)>100 then raise exception 'fulfillment_invalid';end if;
  if jsonb_array_length(v)>0 and not v @> jsonb_build_array(coalesce(row_data->>k,'NOT_CONFIGURED')) and not (k='replenishment_status' and v @> jsonb_build_array(row_data->>'minimum_status')) then matched:=false;end if;
 elsif k in ('on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock') then
  if jsonb_typeof(v)<>'object' then raise exception 'fulfillment_invalid';end if;
  op:=v->>'op';n:=(row_data->>k)::numeric;
  if op='configured' then if n is null then matched:=false;end if;
  elsif op='not_configured' then if n is not null then matched:=false;end if;
  elsif op='positive' then if n is null or n<=0 then matched:=false;end if;
  else
   if op not in ('eq','gt','lt','range') or op is null or jsonb_typeof(v->'value') is distinct from 'number' then raise exception 'fulfillment_invalid';end if;
   a:=(v->>'value')::numeric;b:=(v->>'to')::numeric;
   if op='range' and (b is null or b<a) then raise exception 'fulfillment_invalid';end if;
   if n is null or (op='eq' and n<>a) or (op='gt' and n<=a) or (op='lt' and n>=a) or (op='range' and (n<a or n>b)) then matched:=false;end if;
  end if;
 else raise exception 'fulfillment_invalid';end if;
 end loop;return matched;
end$$;

create or replace function public.warehouse_inventory(factory uuid,page integer default 1,filters jsonb default '{}',sort text default 'name',direction text default 'asc')
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'warehouse','view');
 if page is null or page not between 1 and 1000000 or direction not in ('asc','desc') or direction is null
 or sort is null or sort not in ('name','code','item_type','supply_source','unit','on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock','minimum_status','replenishment_status') then raise exception 'fulfillment_invalid';end if;
 -- Validate filter shape even for an empty catalogue.
 perform private.warehouse_filter_matches('{}',filters);
 with all_rows as materialized(select value r from private.warehouse_inventory_rows(factory) value),
 filtered as materialized(select r from all_rows where private.warehouse_filter_matches(r,filters)),
 ordered as (
 select r,row_number() over(order by
 case when direction='asc' and sort in ('on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock') then (r->>sort)::numeric end asc nulls last,
 case when direction='desc' and sort in ('on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock') then (r->>sort)::numeric end desc nulls last,
 case when direction='asc' and sort not in ('on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock') then lower(r->>sort) end asc nulls last,
 case when direction='desc' and sort not in ('on_hand','semi_finished','in_production','reserved','available','incoming','projected','minimum_stock','maximum_stock') then lower(r->>sort) end desc nulls last,
 r->>'row_key') pos from filtered
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(r order by pos) from ordered where pos between (page-1)*50+1 and page*50),'[]'),
 'total',(select count(*) from filtered),'units',(select coalesce(jsonb_agg(u),'[]') from(select distinct coalesce(r->>'unit','NOT_CONFIGURED') u from all_rows order by u limit 100)x)) into result;
 return result;
end$$;

create or replace function public.confirm_warehouse_replenishment(factory uuid,product uuid,action text,unit text,projected numeric,quantity numeric,request_id uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare prod public.products;level numeric;q numeric;existing uuid;result uuid;payload jsonb;begin
 perform private.require_permission(factory,'warehouse','edit');
 if request_id is null or action is null or action not in ('produce','external') then raise exception 'fulfillment_invalid';end if;
 payload:=jsonb_build_object('product',product,'action',action,'unit',unit,'projected',projected,'quantity',quantity);
 result:=private.fulfillment_retry(factory,request_id,'warehouse_'||action,payload);if result is not null then return result;end if;
 select * into prod from public.products p where p.factory_id=factory and p.id=product and p.stage='finished' for update;
 if not found or unit is distinct from prod.stock_unit or unit is null or prod.minimum_stock is null then raise exception 'fulfillment_product';end if;
 if (action='produce' and prod.supply_source not in ('MANUFACTURED','BOTH')) or (action='external' and prod.supply_source<>'BOTH') then raise exception 'fulfillment_source_decision';end if;
 select o.request_id into existing from public.production_orders o join public.production_requests r on r.id=o.request_id
 where o.factory_id=factory and o.product_id=product and o.unit=confirm_warehouse_replenishment.unit
 and o.status in ('planned','active') and r.request_type='STOCK_REPLENISHMENT' order by o.created_at,o.id limit 1;
 if existing is not null then
  if action='external' then raise exception 'warehouse_stock_changed';end if;
  insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'warehouse_produce',payload,existing,clock_timestamp());return existing;
 end if;
 if exists(select 1 from public.purchase_requisitions pr where pr.factory_id=factory and pr.product_id=product and pr.unit=confirm_warehouse_replenishment.unit and pr.status not in ('RECEIVED','REJECTED','CANCELLED')) then raise exception 'warehouse_stock_changed';end if;
 level:=private.projected_finished(factory,product,unit)+private.purchase_incoming(factory,product,unit);
 if projected is distinct from level or level>prod.minimum_stock then raise exception 'warehouse_stock_changed';end if;
 if action='external' then result:=product;
 else
  q:=case when prod.maximum_stock is not null then prod.maximum_stock-level else quantity end;
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or quantity is distinct from q then raise exception 'fulfillment_invalid';end if;
  result:=gen_random_uuid();
 end if;
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'warehouse_'||action,payload,result,clock_timestamp());
 if action='produce' then
  insert into public.production_requests(id,factory_id,code,name,requested_by,requested_by_name,priority,notes,request_type)
  values(result,factory,'','Stock replenishment',auth.uid(),(select display_name from public.memberships where factory_id=factory and user_id=auth.uid()),'low',
  'Warehouse confirmed; projected='||level||'; minimum='||prod.minimum_stock||'; maximum='||coalesce(prod.maximum_stock::text,'not configured')||'; quantity='||q,'STOCK_REPLENISHMENT');
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(factory,result,product,q,unit);
 end if;return result;
end$$;


create or replace function public.configure_product_stock(factory uuid,product uuid,mode text,unit text,minimum numeric default null,maximum numeric default null)
returns uuid language plpgsql security definer set search_path='' as $$begin
 perform private.require_permission(factory,'warehouse','edit');perform private.fulfillment_lock(factory);
 if mode not in ('MAKE_TO_STOCK','MAKE_TO_ORDER') or unit not in ('meter','piece','kg') or mode is null or unit is null then raise exception 'fulfillment_invalid';end if;
 update public.products set supply_mode=mode,stock_unit=configure_product_stock.unit,minimum_stock=minimum,maximum_stock=maximum where factory_id=factory and id=product and stage='finished';
 if not found then raise exception 'fulfillment_product';end if;perform private.finished_balance(factory,product,unit);
 return product;
end$$;

create function private.guard_wip_location() returns trigger language plpgsql set search_path='' as $$begin
 if new.quantity_available<new.warehouse_quantity then raise exception 'unfinished_insufficient';end if;
 return new;
end$$;
create trigger wip_location_guard before update on public.unfinished_lots for each row execute function private.guard_wip_location();
revoke all on function private.guard_wip_location() from public,anon,authenticated;
create or replace function public.unfinished_inventory(factory uuid,include_consumed boolean default false,page integer default 1,lot_id uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 perform private.require_permission(factory,'orders','view');
 if page is null or page<1 or page>1000000 then raise exception 'history_invalid';end if;
 with lots as materialized(
 select lot.*,lot.quantity_available-lot.warehouse_quantity production_available,e.order_id as item_id,e.input_lot_id as parent_lot_id,e.unit,e.line_id,e.work_center_id,o.product_id,
 r.code as request_code,o.code as item_code,p.name as product_name,p.name_ar as product_name_ar,
 coalesce(l.name,c.name) as origin_name,coalesce(l.name_ar,c.name_ar) as origin_name_ar,
 (select coalesce(jsonb_agg(to_jsonb(d)),'[]') from private.unfinished_destinations(factory,e.order_id) d) as destinations,
 (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at,m.id),'[]') from public.unfinished_movements m where m.factory_id=factory and m.lot_id=lot.id) as movements
 from public.unfinished_lots lot join public.production_entries e on e.factory_id=lot.factory_id and e.id=lot.source_entry_id
 join public.production_orders o on o.factory_id=e.factory_id and o.id=e.order_id
 join public.products p on p.factory_id=o.factory_id and p.id=o.product_id
 left join public.production_requests r on r.factory_id=o.factory_id and r.id=o.request_id
 left join public.production_lines l on l.factory_id=e.factory_id and l.id=e.line_id
 left join public.work_centers c on c.factory_id=e.factory_id and c.id=e.work_center_id
 where lot.factory_id=factory and (lot_id is null or lot.id=lot_id) and (include_consumed or lot.quantity_available>0)),
 paged as(select * from lots order by created_at desc,id limit 50 offset (page-1)*50)
 select jsonb_build_object('total',(select count(*) from lots),'page',page,'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') from paged x)) into result;
 return result;
end$$;

alter table public.products drop constraint products_stock_unit_check;
alter table public.products add constraint products_stock_unit_check check(stock_unit in ('meter','piece','kg'));
alter table public.products add constraint compound_stock_unit check(stock_unit is distinct from 'kg' or product_kind='MANUFACTURED_INTERMEDIATE');
alter table public.production_orders drop constraint production_orders_unit_check;
alter table public.production_orders add constraint production_orders_unit_check check(unit in ('meter','piece','kg','unit'));
alter table public.work_center_capabilities drop constraint work_center_capabilities_rate_unit_check;
alter table public.work_center_capabilities add constraint work_center_capabilities_rate_unit_check check(rate_unit in ('meter','piece','kg'));
alter table public.finished_goods_balances drop constraint finished_goods_balances_unit_check;
alter table public.finished_goods_balances add constraint finished_goods_balances_unit_check check(unit in ('meter','piece','kg'));
alter table public.production_entries drop constraint entry_recording_unit;
alter table public.production_entries add constraint entry_recording_unit check(recording_version=1 or
 (recording_version=2 and technician_id is not null and unit in ('meter','piece','kg') and ((line_id is not null and work_center_id is null) or (line_id is null and work_center_id is not null))));
CREATE OR REPLACE FUNCTION public.adjust_finished_stock(factory uuid, product uuid, unit text, quantity numeric, reason text, request_id uuid DEFAULT gen_random_uuid())
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$declare old uuid;result uuid:=gen_random_uuid();p jsonb:=jsonb_build_object('product',product,'unit',unit,'quantity',quantity,'reason',reason);l record;begin
 perform private.require_permission(factory,'warehouse','edit');old:=private.fulfillment_retry(factory,request_id,'adjust',p);if old is not null then return old;end if;
 if quantity is null or quantity=0 or quantity::text in ('NaN','Infinity','-Infinity') or unit not in ('meter','piece','kg') or length(trim(coalesce(reason,''))) not between 3 and 2000
 or not exists(select 1 from public.products where factory_id=factory and id=product and stage='finished') then raise exception 'fulfillment_invalid';end if;
 perform private.finished_balance(factory,product,unit);
 if exists(select 1 from public.finished_goods_balances b where b.factory_id=factory and b.product_id=product and b.unit=adjust_finished_stock.unit and b.on_hand+quantity<b.reserved) then raise exception 'fulfillment_stock_committed';end if;
 update public.finished_goods_balances set on_hand=on_hand+quantity where factory_id=factory and product_id=product and finished_goods_balances.unit=adjust_finished_stock.unit;
 insert into public.finished_goods_movements(id,factory_id,product_id,unit,kind,stock_delta,reason,created_by) values(result,factory,product,unit,'adjustment',quantity,reason,auth.uid());
 -- Fill genuine unallocated demand, not an existing production commitment a second time.
 for l in select t_l.id from public.sales_order_lines t_l join public.sales_orders t_s on t_s.id=t_l.order_id where t_l.factory_id=factory and t_l.product_id=product and t_l.unit=adjust_finished_stock.unit and t_s.status='approved' order by t_s.created_at,t_l.id loop
 perform private.allocate_sales_line(factory,l.id);end loop;
 perform private.replenish_finished(factory,product);
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'adjust',p,result,clock_timestamp());return result;
end$function$;

CREATE OR REPLACE FUNCTION private.capture_finished_good()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare job public.production_orders;received numeric;delta numeric;leftover numeric;take numeric;a record;correction uuid;begin
 select * into job from public.production_orders where factory_id=new.factory_id and id=new.order_id;
 if new.unit not in ('meter','piece','kg') or new.unit is null or not exists(select 1 from public.products where id=job.product_id and stage='finished') then return new;end if;
 perform private.fulfillment_lock(new.factory_id);
 select received_good into received from public.finished_goods_entry_receipts where factory_id=new.factory_id and entry_id=new.id for update;
 -- Historical entries are not warehouse receipts. Editing one must not fabricate an opening stock balance.
 if tg_op='UPDATE' and not found then return new;end if;
 delta:=coalesce(new.effective_good,0)-coalesce(received,0);
 if delta=0 then
 if tg_op='INSERT' then insert into public.finished_goods_entry_receipts values(new.factory_id,new.id,0);end if;
 return new;end if;
 perform private.finished_balance(new.factory_id,job.product_id,new.unit);
 if delta<0 and exists(select 1 from public.finished_goods_balances where factory_id=new.factory_id and product_id=job.product_id and unit=new.unit and on_hand+delta<reserved)
 then raise exception 'fulfillment_stock_committed';end if;
 update public.finished_goods_balances set on_hand=on_hand+delta where factory_id=new.factory_id and product_id=job.product_id and unit=new.unit;
 insert into public.finished_goods_entry_receipts values(new.factory_id,new.id,new.effective_good)
 on conflict(factory_id,entry_id) do update set received_good=excluded.received_good;
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,entry_id,reason,created_by)
 values(new.factory_id,job.product_id,new.unit,case when tg_op='INSERT' then 'production_receipt' else 'production_correction' end,delta,new.id,
 case when tg_op='UPDATE' then (select c.reason from public.production_entry_corrections c where c.entry_id=new.id order by c.created_at desc,c.id desc limit 1) end,auth.uid());
 leftover:=greatest(delta,0);
 for a in select t_a.id,t_a.line_id,t_a.quantity from public.sales_incoming_allocations t_a
 join public.sales_order_lines l on l.id=t_a.line_id join public.sales_orders s on s.id=l.order_id
 where t_a.factory_id=new.factory_id and t_a.item_id=job.id and t_a.quantity>0 and s.status='approved' order by s.created_at,t_a.id for update of t_a loop
 take:=least(leftover,a.quantity);exit when take<=0;
 perform private.reserve_finished(new.factory_id,a.line_id,take);
 update public.sales_incoming_allocations set quantity=quantity-take,received_quantity=received_quantity+take where id=a.id;
 leftover:=leftover-take;end loop;
 if delta>0 then perform private.reserve_received_stock(new.factory_id,job.product_id,new.unit);end if;
 return new;
end$function$;

CREATE OR REPLACE FUNCTION private.configure_center_capabilities(f uuid, w uuid, capabilities jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.require_permission(f,'centers','edit');
  perform 1 from public.work_centers where id=w and factory_id=f and not archived for update;
  if not found then raise exception 'not_found'; end if;
  if capabilities is null or jsonb_typeof(capabilities)<>'array' then
    raise exception 'invalid_capabilities'; end if;
  if exists(
    select 1 from jsonb_to_recordset(capabilities)
      x(product_id uuid,rate numeric,rate_unit text,setup_minutes integer)
    where x.rate is null or x.rate<=0 or x.rate_unit not in ('meter','piece','kg') or
      x.rate_unit is null or coalesce(x.setup_minutes,0) not between 0 and 10080
  ) then raise exception 'invalid_capabilities'; end if;
  delete from public.work_center_capabilities where factory_id=f and work_center_id=w;
  insert into public.work_center_capabilities
    (factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)
  select f,w,x.product_id,x.rate,x.rate_unit,coalesce(x.setup_minutes,0)
  from jsonb_to_recordset(capabilities)
    x(product_id uuid,rate numeric,rate_unit text,setup_minutes integer);
end;
$function$;

CREATE OR REPLACE FUNCTION private.plan_product_item(f uuid, item uuid, target_line uuid, planned_start timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target public.production_orders%rowtype;
  matches integer;
  typed_matches integer;
  slowest numeric;
  fastest numeric;
  shortest_setup integer;
  longest_setup integer;
  minutes_required numeric;
  effective_start timestamptz;
  planned_finish timestamptz;
begin
  perform private.require_permission(f,'orders','edit');
  select * into target from public.production_orders
    where factory_id=f and id=item for update;
  if not found then raise exception 'not_found'; end if;
  if target.status<>'planned' or target.produced_quantity>0 then
    raise exception 'planning_already_started'; end if;
  if target_line is null and planned_start is null then
    update public.production_orders set line_id=null,start_time=null,expected_finish=null
      where factory_id=f and id=item;
    return item;
  end if;
  if target_line is null or planned_start is null or planned_start<now()-interval '1 minute' then
    raise exception 'planning_invalid_start'; end if;
  perform 1 from public.production_lines
    where factory_id=f and id=target_line and not archived for update;
  if not found then raise exception 'planning_incompatible_line'; end if;
  select count(*),count(*) filter (where cap.rate_unit=target.unit),
    min(cap.rate) filter (where cap.rate_unit=target.unit),
    max(cap.rate) filter (where cap.rate_unit=target.unit),
    min(cap.setup_minutes),max(cap.setup_minutes)
    into matches,typed_matches,slowest,fastest,shortest_setup,longest_setup
  from public.work_centers center
  join public.work_center_capabilities cap
    on cap.factory_id=center.factory_id and cap.work_center_id=center.id
      and cap.product_id=target.product_id
  where center.factory_id=f and center.line_id=target_line and not center.archived;
  if matches=0 then raise exception 'planning_incompatible_line'; end if;
  if target.unit not in ('meter','piece','kg') or typed_matches<>matches then
    raise exception 'planning_missing_rate'; end if;
  if slowest<>fastest then raise exception 'planning_ambiguous_rate'; end if;
  if shortest_setup<>longest_setup then raise exception 'planning_ambiguous_setup'; end if;
  minutes_required:=ceil(target.target_quantity / slowest * 60)+shortest_setup;
  if minutes_required<1 or minutes_required>5256000 then
    raise exception 'planning_invalid_quantity'; end if;
  effective_start:=private.next_working_start(f,planned_start);
  planned_finish:=private.finish_after_working_minutes(f,effective_start,minutes_required::integer);
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active') and
      (other.start_time is null or other.expected_finish is null)
  ) then raise exception 'planning_unknown_block'; end if;
  if exists(
    select 1 from public.production_orders other
    where other.factory_id=f and other.id<>item and other.line_id=target_line
      and other.status in ('planned','active')
      and effective_start<other.expected_finish and planned_finish>other.start_time
  ) then raise exception 'planning_overlap'; end if;
  update public.production_orders set
    line_id=target_line,start_time=effective_start,expected_finish=planned_finish
    where factory_id=f and id=item;
  return item;
end;
$function$;

CREATE OR REPLACE FUNCTION private.production_recording_units(f uuid)
 RETURNS TABLE(unit_kind text, unit_id uuid, item_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select 'line',l.id,o.id from public.production_lines l
 join public.production_orders o on o.factory_id=l.factory_id and o.line_id=l.id
 where l.factory_id=f and not l.archived and o.status='active' and o.actual_start is not null and o.actual_finish is null and o.unit in ('meter','piece','kg')
 union all
 select 'machine',c.id,o.id from public.work_centers c
 join public.production_orders o on o.factory_id=c.factory_id and
 o.id=private.execution_center_order(c.factory_id,c.id,c.line_id,c.order_id)
 where c.factory_id=f and not c.archived and c.line_id is null and c.dependency_mode='independent'
 and o.status='active' and o.actual_start is not null and o.actual_finish is null
 and not exists(select 1 from public.production_transfers t where t.factory_id=f and t.ended_at is null
   and c.id in(t.original_id,t.alternative_id))
 and exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=c.id
   and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0);
$function$;

CREATE OR REPLACE FUNCTION public.production_history(factory uuid, filters jsonb DEFAULT '{}'::jsonb, sort_key text DEFAULT 'date'::text, sort_direction text DEFAULT 'desc'::text, page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb; zone text;metric text; begin
 perform private.require_permission(factory,'orders','view');
 if sort_key not in ('date','good','scrap','unfinished','unit','technician','shift') or sort_direction not in ('asc','desc')
 or page is null or page<1 or page>1000000 or jsonb_typeof(filters)<>'object' then raise exception 'history_invalid';end if;
 if filters is null or jsonb_typeof(filters)<>'object' or length(filters::text)>12000 then raise exception 'history_invalid';end if;
 for metric in select unnest(array['good','scrap','unfinished']) loop
   perform private.history_number_match(0,filters->>(metric||'_op'),filters->>(metric||'_min'),filters->>(metric||'_max'));
   if nullif(filters->>(metric||'_op'),'') is not null and coalesce(filters->>'measurement_unit','') not in ('meter','piece','kg') then raise exception 'history_unit_required';end if;
 end loop;
 if nullif(filters->>'from','') is not null and nullif(filters->>'to','') is not null and (filters->>'from')::date>(filters->>'to')::date then raise exception 'history_invalid';end if;
 if coalesce(filters->>'scrap_metric','quantity') not in ('quantity','percentage') or coalesce(filters->>'scrap_scope','row') not in ('row','shift') then raise exception 'history_invalid';end if;
 select timezone into zone from public.factories where id=factory;
 with base as materialized (
 select e.*,100*e.effective_scrap/nullif(e.effective_good+e.effective_scrap+coalesce(e.effective_unfinished,0),0) as scrap_percentage,o.request_id as production_request_id,o.product_id,r.code as request_code,o.code as item_code,
 p.name as product_name,p.name_ar as product_name_ar,
 coalesce(l.name,c.name) as unit_name,coalesce(l.name_ar,c.name_ar) as unit_name_ar,
 case when e.line_id is not null then 'line:'||e.line_id else 'machine:'||e.work_center_id end as unit_key,
 tech.display_name as technician_name,actor.display_name as submitter_name,
 sh.name as shift_name,sh.name_ar as shift_name_ar,
 to_jsonb(o) as history_item,
 exists(select 1 from public.production_entry_corrections x where x.factory_id=factory and x.entry_id=e.id) as corrected
 from public.production_entries e join public.production_orders o on o.id=e.order_id and o.factory_id=e.factory_id
 left join public.production_requests r on r.id=o.request_id and r.factory_id=e.factory_id
 left join public.products p on p.id=o.product_id and p.factory_id=e.factory_id
 left join public.production_lines l on l.id=e.line_id and l.factory_id=e.factory_id
 left join public.work_centers c on c.id=e.work_center_id and c.factory_id=e.factory_id
 left join public.memberships tech on tech.id=e.technician_id and tech.factory_id=e.factory_id
 left join public.memberships actor on actor.user_id=e.created_by and actor.factory_id=e.factory_id
 left join public.production_shifts sh on sh.id=e.shift_id and sh.factory_id=e.factory_id
 where e.factory_id=factory),
 selected as materialized (select * from base b where
 private.history_values_match(b.production_request_id::text,filters->>'request')
 and private.history_values_match(b.product_id::text,filters->>'product')
 and private.history_values_match(b.technician_id::text,filters->>'technician')
 and private.history_values_match(b.unit_key,filters->>'unit')
 and private.history_values_match(b.shift_id::text,filters->>'shift')
 and private.history_values_match(case when b.corrected then 'yes' else 'no' end,nullif(filters->>'corrected','all'))
 and (nullif(filters->>'from','') is null or b.created_at>=((filters->>'from')::date::timestamp at time zone zone))
 and (nullif(filters->>'to','') is null or b.created_at<(((filters->>'to')::date+1)::timestamp at time zone zone))
 and (nullif(filters->>'measurement_unit','') is null or b.unit=filters->>'measurement_unit')
 and private.history_number_match(b.effective_good,filters->>'good_op',filters->>'good_min',filters->>'good_max')
 and private.history_number_match(coalesce(b.effective_unfinished,0),filters->>'unfinished_op',filters->>'unfinished_min',filters->>'unfinished_max')
 and (coalesce(filters->>'scrap','all')<>'has' or b.effective_scrap>0)
 and (nullif(filters->>'minimum_scrap','') is null or b.effective_scrap>=(filters->>'minimum_scrap')::numeric)),
 scoped as materialized (select selected.*,
 100*sum(effective_scrap) over(partition by shift_id,unit)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)) over(partition by shift_id,unit),0) as shift_scrap_percentage
 from selected),
 filtered as materialized(select * from scoped where private.history_number_match(
 case when filters->>'scrap_metric'='percentage' then case when filters->>'scrap_scope'='shift' then shift_scrap_percentage else scrap_percentage end else effective_scrap end,
 filters->>'scrap_op',filters->>'scrap_min',filters->>'scrap_max')),
 ranked as (select *,row_number() over(order by
 case when sort_key='date' and sort_direction='asc' then created_at end asc,
 case when sort_key='date' and sort_direction='desc' then created_at end desc,
 case when sort_key='good' and sort_direction='asc' then effective_good end asc,
 case when sort_key='good' and sort_direction='desc' then effective_good end desc,
 case when sort_key='scrap' and sort_direction='asc' then effective_scrap end asc,
 case when sort_key='scrap' and sort_direction='desc' then effective_scrap end desc,
 case when sort_key='unfinished' and sort_direction='asc' then coalesce(effective_unfinished,0) end asc,
 case when sort_key='unfinished' and sort_direction='desc' then coalesce(effective_unfinished,0) end desc,
 case when sort_key='unit' and sort_direction='asc' then unit_name end asc,
 case when sort_key='unit' and sort_direction='desc' then unit_name end desc,
 case when sort_key='technician' and sort_direction='asc' then technician_name end asc,
 case when sort_key='technician' and sort_direction='desc' then technician_name end desc,
 case when sort_key='shift' and sort_direction='asc' then shift_name end asc,
 case when sort_key='shift' and sort_direction='desc' then shift_name end desc,
 created_at desc,id) as position from filtered),
 totals as (select coalesce(unit,'unknown') as measurement_unit,count(*) as records,
 sum(effective_good) as good,sum(effective_scrap) as scrap,sum(coalesce(effective_unfinished,0)) as unfinished,
 100*sum(effective_scrap)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)),0) as scrap_percentage from filtered where unit in ('meter','piece','kg') group by coalesce(unit,'unknown')),
 shift_totals as (select shift_id,shift_name,shift_name_ar,unit as measurement_unit,count(*) as records,sum(effective_scrap) as scrap,
 sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)) as output,
 100*sum(effective_scrap)/nullif(sum(effective_good+effective_scrap+coalesce(effective_unfinished,0)),0) as scrap_percentage
 from filtered where unit in ('meter','piece','kg') group by shift_id,shift_name,shift_name_ar,unit),
 groups as (select coalesce(unit,'unknown') as measurement_unit,'unit' as kind,unit_key as identity,
 unit_name as name,unit_name_ar as name_ar,sum(effective_scrap) as scrap from filtered group by coalesce(unit,'unknown'),unit_key,unit_name,unit_name_ar
 union all select coalesce(unit,'unknown'),'shift',shift_id::text,shift_name,shift_name_ar,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),shift_id,shift_name,shift_name_ar
 union all select coalesce(unit,'unknown'),'technician',technician_id::text,technician_name,technician_name,sum(effective_scrap) from filtered group by coalesce(unit,'unknown'),technician_id,technician_name),
 winners as (select *,row_number() over(partition by measurement_unit,kind order by scrap desc,identity nulls last) as rank from groups)
 select jsonb_build_object('total',(select count(*) from filtered),'page',page,'page_size',50,
 'rows',(select coalesce(jsonb_agg(to_jsonb(x) order by x.position),'[]') from
 (select ranked.*,(select coalesce(jsonb_agg(to_jsonb(c) order by c.created_at,c.id),'[]') from
 public.production_entry_corrections c where c.factory_id=factory and c.entry_id=ranked.id) as corrections
 from ranked where position between (page-1)*50+1 and page*50) x),
 'unknown_unit_records',(select count(*) from filtered where unit is null or unit not in ('meter','piece','kg')),
 'totals',(select coalesce(jsonb_agg(to_jsonb(t)),'[]') from totals t),
 'shift_totals',(select coalesce(jsonb_agg(to_jsonb(st)),'[]') from shift_totals st),
 'highest',(select coalesce(jsonb_agg(to_jsonb(w)),'[]') from winners w where rank=1 and scrap>0 and measurement_unit in ('meter','piece','kg'))) into result;
 return result;
end$function$;

CREATE OR REPLACE FUNCTION private.unfinished_destinations(f uuid, i uuid)
 RETURNS TABLE(unit_kind text, unit_id uuid, item_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select 'line',l.id,o.id from public.production_lines l join public.production_orders o on o.factory_id=l.factory_id and o.id=i
 where l.factory_id=f and not l.archived and l.paused_at is null and o.unit in ('meter','piece','kg')
 and o.status in ('active','completed')
 and not exists(select 1 from public.production_orders busy where busy.factory_id=f and busy.line_id=l.id and busy.status='active' and busy.id<>i)
 and exists(select 1 from public.work_centers c join public.work_center_capabilities cap on cap.factory_id=c.factory_id and cap.work_center_id=c.id
 where c.factory_id=f and c.line_id=l.id and not c.archived and c.dependency_mode<>'independent' and c.status in ('idle','running')
 and not exists(select 1 from public.production_transfers tr where tr.factory_id=f and tr.ended_at is null and c.id in(tr.original_id,tr.alternative_id))
 and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0)
 union all
 select 'machine',c.id,o.id from public.work_centers c join public.production_orders o on o.factory_id=c.factory_id and o.id=i
 where c.factory_id=f and not c.archived and c.line_id is null and c.dependency_mode='independent'
 and c.status in ('idle','running') and o.status in ('active','completed') and o.unit in ('meter','piece','kg')
 and (private.execution_center_order(f,c.id,c.line_id,c.order_id) is null or private.execution_center_order(f,c.id,c.line_id,c.order_id)=i)
 and not exists(select 1 from public.production_transfers tr where tr.factory_id=f and tr.ended_at is null and c.id in(tr.original_id,tr.alternative_id))
 and exists(select 1 from public.work_center_capabilities cap where cap.factory_id=f and cap.work_center_id=c.id and cap.product_id=o.product_id and cap.rate_unit=o.unit and cap.rate>0);
$function$;

CREATE OR REPLACE FUNCTION private.correct_production(f uuid, e uuid, good numeric, scrap numeric, reason text, confirmed boolean, r uuid, shift uuid, change_shift boolean, unfinished numeric, work_note text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare original public.production_entries;job public.production_orders;previous public.production_entry_corrections;result uuid;total numeric;new_shift uuid;lot public.unfinished_lots;delta numeric;new_lot uuid;
begin
 perform private.require_permission(f,'orders','edit');
 perform private.require_permission(f,'orders','view');
 if r is null or good is null or scrap is null or good<0 or scrap<0
   or good::text in ('NaN','Infinity','-Infinity') or scrap::text in ('NaN','Infinity','-Infinity')
   or length(trim(coalesce(reason,''))) not between 3 and 2000 then raise exception 'recording_correction_reason';end if;
 if unfinished is not null and (unfinished<0 or unfinished::text in ('NaN','Infinity','-Infinity') or (unfinished>0 and length(trim(coalesce(work_note,''))) not between 3 and 2000)) then raise exception 'unfinished_invalid';end if;
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||':structure',0));
 perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(f::text||r::text,0));
 select * into previous from public.production_entry_corrections c where c.factory_id=f and c.request_id=r;
 if found then
   if previous.entry_id<>e or previous.corrected_good<>good or previous.corrected_scrap<>scrap or previous.reason<>reason
     or (unfinished is not null and coalesce(previous.corrected_unfinished,0)<>unfinished)
     or (work_note is not null and previous.corrected_remaining_work is distinct from trim(work_note))
     or previous.shift_changed is distinct from change_shift or (change_shift and previous.corrected_shift_id is distinct from shift) or previous.created_by<>auth.uid() or previous.overproduction_confirmed<>coalesce(confirmed,false) then raise exception 'request_conflict';end if;
   return previous.id;
 end if;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e;
 if not found then raise exception 'invalid_order';end if;
 select * into job from public.production_orders o where o.factory_id=f and o.id=original.order_id for update;
 select * into original from public.production_entries x where x.factory_id=f and x.id=e for update;
 unfinished:=coalesce(unfinished,original.effective_unfinished,0);
 work_note:=coalesce(trim(work_note),original.effective_remaining_work,'');
 if unfinished>0 and (length(work_note) not between 3 and 2000 or original.unit not in ('meter','piece','kg') or original.unit is null) then raise exception 'unfinished_invalid';end if;
 if original.input_lot_id is not null and good+scrap+unfinished<>original.input_quantity then raise exception 'unfinished_conservation';end if;
 select * into lot from public.unfinished_lots x where x.factory_id=f and x.source_entry_id=e for update;
 delta:=unfinished-coalesce(original.effective_unfinished,0);
 if lot.id is not null and lot.quantity_available+delta<lot.warehouse_quantity then raise exception 'unfinished_already_consumed';end if;
 new_shift:=case when change_shift then shift else original.shift_id end;
 if change_shift and new_shift is distinct from original.shift_id then perform private.validate_production_shift(f,new_shift);end if;
 total:=job.good_quantity-original.effective_good+good;
 if total>job.target_quantity and not coalesce(confirmed,false) then raise exception 'recording_overproduction_confirmation';end if;
 insert into public.production_entry_corrections(factory_id,entry_id,previous_good,previous_scrap,corrected_good,corrected_scrap,reason,created_by,request_id,overproduction_confirmed,previous_shift_id,corrected_shift_id,shift_changed,previous_unfinished,corrected_unfinished,previous_remaining_work,corrected_remaining_work)
 values(f,e,original.effective_good,original.effective_scrap,good,scrap,reason,auth.uid(),r,coalesce(confirmed,false),original.shift_id,new_shift,coalesce(change_shift,false),coalesce(original.effective_unfinished,0),unfinished,original.effective_remaining_work,work_note) returning id into result;
 update public.production_orders set produced_quantity=produced_quantity-original.effective_good-original.effective_scrap+good+scrap,
   rejected_quantity=rejected_quantity-original.effective_scrap+scrap where id=job.id;
 update public.production_entries set effective_good=good,effective_scrap=scrap,shift_id=new_shift,effective_unfinished=unfinished,effective_remaining_work=work_note where id=e;
 if lot.id is null and unfinished>0 then
   insert into public.unfinished_lots(factory_id,source_entry_id,quantity_created,quantity_available,remaining_work,created_at,created_by)
   values(f,e,unfinished,unfinished,work_note,clock_timestamp(),auth.uid()) returning id into new_lot;
 elsif lot.id is not null then
   new_lot:=lot.id;
   update public.unfinished_lots set quantity_created=quantity_created+delta,quantity_available=quantity_available+delta,
   remaining_work=case when unfinished>0 then work_note else remaining_work end where id=lot.id;
 end if;
 if new_lot is not null and delta<>0 then
   insert into public.unfinished_movements(factory_id,lot_id,entry_id,correction_id,kind,quantity,created_by)
   values(f,new_lot,e,result,'corrected',delta,auth.uid());
 end if;
 return result;
end$function$;

CREATE OR REPLACE FUNCTION private.create_production_request(f uuid, request_name text, request_priority text, request_required_by timestamp with time zone, request_notes text, request_items jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result_id uuid; entry jsonb; product uuid; amount numeric; item_unit text;
 seen uuid[] := '{}'; actor_name text; internal_reason text;
begin
 perform private.require_permission(f,'orders','create');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 if length(btrim(coalesce(request_name,''))) not between 1 and 200 then
  raise exception 'request_name_required';end if;
 if coalesce(request_priority,'normal') not in ('low','normal','high','urgent') then
  raise exception 'invalid_priority';end if;
 internal_reason:=regexp_replace(coalesce(request_notes,''),'^\s+|\s+$','','g');
 if internal_reason='' then raise exception 'internal_reason_required';end if;
 if length(internal_reason)>2000 then raise exception 'invalid_notes';end if;
 if jsonb_typeof(request_items) is distinct from 'array' or jsonb_array_length(request_items) not between 1 and 100 then
  raise exception 'request_items_required';end if;
 select m.display_name into actor_name from public.memberships m
  where m.factory_id=f and m.user_id=auth.uid() and m.status='approved';
 actor_name:=coalesce(nullif(btrim(actor_name),''),(select split_part(u.email,'@',1) from auth.users u where u.id=auth.uid()));
 insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,required_by,notes,request_type,created_at)
 values(f,'',btrim(request_name),auth.uid(),actor_name,coalesce(request_priority,'normal'),request_required_by,internal_reason,'INTERNAL_PRODUCTION',clock_timestamp())
 returning id into result_id;
 for entry in select value from jsonb_array_elements(request_items) loop
  if jsonb_typeof(entry) is distinct from 'object' or exists(select 1 from jsonb_object_keys(entry) k where k not in ('product_id','quantity','unit')) then
   raise exception 'invalid_request_item';end if;
  product:=nullif(entry->>'product_id','')::uuid;amount:=nullif(entry->>'quantity','')::numeric;item_unit:=entry->>'unit';
  if product is null or not exists(select 1 from public.products p where p.factory_id=f and p.id=product) then
   raise exception 'invalid_request_product';end if;
  if exists(select 1 from public.products p where p.factory_id=f and p.id=product and p.supply_source='EXTERNAL') then raise exception 'fulfillment_source_decision';end if;
  if product=any(seen) then raise exception 'duplicate_request_product';end if;
  if amount is null or amount<=0 or amount::text in ('NaN','Infinity','-Infinity') then raise exception 'invalid_request_quantity';end if;
  if item_unit is null or item_unit not in ('meter','piece','kg') or (item_unit='kg' and not exists(select 1 from public.products where factory_id=f and id=product and product_kind='MANUFACTURED_INTERMEDIATE' and stock_unit='kg')) then raise exception 'invalid_request_unit';end if;
  seen:=array_append(seen,product);
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit)
   values(f,result_id,product,amount,item_unit);
 end loop;
 return result_id;
end;
$function$;
 -- Kg loss measurements retain the existing loss review and compatibility guards.
alter table public.production_loss_recovery_rates drop constraint production_loss_recovery_rates_unit_check;
alter table public.production_loss_recovery_rates add constraint production_loss_recovery_rates_unit_check check(unit in ('meter','piece','kg'));
alter table public.production_loss_actuals drop constraint production_loss_actual_output_unit;
alter table public.production_loss_actuals add constraint production_loss_actual_output_unit check((actual_lost_output_quantity is null and actual_lost_output_unit is null) or (actual_lost_output_quantity is not null and actual_lost_output_unit in ('meter','piece','kg')));
CREATE OR REPLACE FUNCTION public.record_production_loss_actuals(factory uuid, event uuid, scrap_quantity numeric, scrap_unit text, recovery_minutes numeric, shutdown_scrap numeric, restart_scrap numeric, actual_loss_minutes numeric, actual_lost_output_quantity numeric, actual_lost_output_unit text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result_id uuid; total_scrap numeric := scrap_quantity;
  tolerance numeric;
begin
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.downtime_events
    where factory_id=factory and id=event and ended_at is not null)
    then raise exception 'downtime_not_reviewable'; end if;
  if (scrap_quantity is not null and scrap_quantity < 0) or
    (shutdown_scrap is not null and shutdown_scrap < 0) or
    (restart_scrap is not null and restart_scrap < 0) or
    (recovery_minutes is not null and recovery_minutes < 0) or
    (actual_loss_minutes is not null and actual_loss_minutes < 0) or
    (actual_lost_output_quantity is not null and actual_lost_output_quantity < 0)
    then raise exception 'loss_actual_nonnegative'; end if;
  if total_scrap is null and (shutdown_scrap is null) <> (restart_scrap is null)
    then raise exception 'loss_scrap_need_total_or_both'; end if;
  if total_scrap is null and shutdown_scrap is not null then
    total_scrap := shutdown_scrap + restart_scrap;
  end if;
  if total_scrap is not null then
    if scrap_unit not in ('kg','piece') or scrap_unit is null
      then raise exception 'loss_actual_invalid_unit'; end if;
    tolerance := greatest(0.000001,total_scrap*0.000000001);
    if coalesce(shutdown_scrap,0)+coalesce(restart_scrap,0) > total_scrap+tolerance
      then raise exception 'loss_scrap_breakdown_exceeds_total'; end if;
    if shutdown_scrap is not null and restart_scrap is not null and
      abs(total_scrap-shutdown_scrap-restart_scrap)>tolerance
      then raise exception 'loss_scrap_breakdown_mismatch'; end if;
  elsif scrap_unit is not null then raise exception 'loss_actual_invalid_unit';
  end if;
  if (actual_lost_output_quantity is null) <> (actual_lost_output_unit is null)
    or (actual_lost_output_quantity is not null and
      actual_lost_output_unit not in ('meter','piece','kg'))
    then raise exception 'loss_actual_invalid_unit'; end if;
  if total_scrap is null and recovery_minutes is null and
    actual_loss_minutes is null and actual_lost_output_quantity is null
    then raise exception 'loss_actual_at_least_one'; end if;
  insert into public.production_loss_actuals(factory_id,event_id,
    scrap_quantity,scrap_unit,recovery_minutes,shutdown_scrap_quantity,
    restart_scrap_quantity,actual_loss_minutes,actual_lost_output_quantity,
    actual_lost_output_unit,recorded_by)
  values(factory,event,total_scrap,scrap_unit,recovery_minutes,shutdown_scrap,
    restart_scrap,actual_loss_minutes,actual_lost_output_quantity,
    actual_lost_output_unit,auth.uid())
  on conflict(factory_id,event_id) do update set
    scrap_quantity=excluded.scrap_quantity,scrap_unit=excluded.scrap_unit,
    recovery_minutes=excluded.recovery_minutes,
    shutdown_scrap_quantity=excluded.shutdown_scrap_quantity,
    restart_scrap_quantity=excluded.restart_scrap_quantity,
    actual_loss_minutes=excluded.actual_loss_minutes,
    actual_lost_output_quantity=excluded.actual_lost_output_quantity,
    actual_lost_output_unit=excluded.actual_lost_output_unit,
    recorded_by=auth.uid(),recorded_at=clock_timestamp()
  returning id into result_id;
  return result_id;
end;
$function$;
