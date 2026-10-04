-- Warehouse requester UX; existing Purchasing and receipt lifecycle retained.
-- Preserve existing compound-only kg stock ownership in manual purchases.
create or replace function private.warehouse_inventory_purchase(factory uuid,payload jsonb,request_id uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare result uuid;old uuid;target uuid;mat uuid;prod uuid;u text;configured text;label text;kind text;q numeric;
 actor_name text;context jsonb;specification text;
begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'warehouse','edit');
 old:=private.fulfillment_retry(factory,request_id,'supply_purchase_inventory',payload);
 if old is not null then return old;end if;
 if payload->>'item'='other' then
  q:=(payload->>'quantity')::numeric;u:=coalesce(nullif(btrim(payload->>'unit'),''),'piece');specification:=btrim(coalesce(payload->>'details',''));
  if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or u not in ('piece','kg','meter') or length(specification) not between 1 and 4000 then raise exception 'supply_invalid';end if;
  actor_name:=coalesce((select display_name from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved'),'');
  insert into public.purchase_requisitions(factory_id,item_name,quantity,unit,details,source_context,requested_by,requested_by_name)
   values(factory,left(specification,200),q,u,specification,'Warehouse',auth.uid(),actor_name) returning id into result;
  perform private.supply_event(factory,result,'');
  insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'supply_purchase_inventory',payload,result,clock_timestamp());
  return result;
 end if;
 target:=(payload->>'item')::uuid;
 select m.id,m.name,m.unit into mat,label,configured from public.materials m where m.factory_id=factory and m.id=target;
 if not found then
  select p.id,p.name,p.stock_unit,p.product_kind into prod,label,configured,kind
   from public.products p where p.factory_id=factory and p.id=target and p.stage='finished';
  if not found then raise exception 'supply_invalid';end if;
 end if;
 u:=coalesce(nullif(btrim(payload->>'unit'),''),configured,'piece');
 q:=(payload->>'quantity')::numeric;specification:=btrim(coalesce(payload->>'details',''));
 if q is null or q<=0 or q::text in ('NaN','Infinity','-Infinity') or length(specification)>4000
  or (configured is not null and u<>configured)
  or (configured is null and (u not in ('piece','meter','kg') or (kind='MANUFACTURED_INTERMEDIATE' and u<>'kg')))
  or (prod is not null and kind <> 'MANUFACTURED_INTERMEDIATE' and u='kg')
  or length(u) not between 1 and 50 then raise exception 'supply_invalid';end if;
 if exists(select 1 from public.purchase_requisitions r where r.factory_id=factory and r.unit=u
  and (r.material_id=mat or r.product_id=prod) and r.status not in ('RECEIVED','REJECTED','CANCELLED')) then raise exception 'supply_duplicate';end if;
 actor_name:=coalesce((select display_name from public.memberships where factory_id=factory and user_id=auth.uid() and status='approved'),'');
 select value into context from private.warehouse_inventory_rows(factory) value where value->>'id'=target::text;
 insert into public.purchase_requisitions(factory_id,material_id,product_id,item_name,quantity,unit,details,source_context,requested_by,requested_by_name,stock_context)
  values(factory,mat,prod,label,q,u,specification,'Warehouse',auth.uid(),actor_name,coalesce(context,'{}'::jsonb)||jsonb_build_object('manual_purchase',true)) returning id into result;
 perform private.supply_event(factory,result,'');
 insert into public.fulfillment_commands values(factory,request_id,auth.uid(),'supply_purchase_inventory',payload,result,clock_timestamp());
 return result;
end$$;
revoke all on function private.warehouse_inventory_purchase(uuid,jsonb,uuid) from public,anon,authenticated;


-- Preserve the existing command body; widen only original-requester pre-order cancellation.
do $migration$
declare body text;old_rule text:='r.status not in (''REQUESTED'',''NEEDS_CLARIFICATION'')';
begin
 body:=pg_get_functiondef('private.apply_supply_command(uuid,text,jsonb,uuid)'::regprocedure);
 if strpos(body,old_rule)=0 then raise exception 'expected_requester_cancel_rule_missing';end if;
 body:=replace(body,old_rule,'r.status not in (''REQUESTED'',''UNDER_REVIEW'',''NEEDS_CLARIFICATION'')');
 execute body;
end$migration$;
revoke all on function private.apply_supply_command(uuid,text,jsonb,uuid) from public,anon,authenticated;

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
  with data as materialized(select r.*,(select name from public.suppliers where factory_id=factory and id=r.supplier_id) supplier_name from public.purchase_requisitions r where r.factory_id=factory and (broad or r.requested_by=auth.uid())
   and (mode<>'stock_purchases' or r.material_id is not null or r.product_id is not null or (r.source_context='Warehouse' and r.requested_by=auth.uid()))
   and (coalesce(filters->>'search','')='' or lower(r.item_name||' '||r.code||' '||r.requested_by_name||' '||r.source_context) like '%'||lower(filters->>'search')||'%')
   and (coalesce(jsonb_array_length(filters->'status'),0)=0 or filters->'status' @> jsonb_build_array(r.status))
   and (coalesce(filters->>'source_context','')='' or strpos(lower(r.source_context),lower(filters->>'source_context'))>0)
   and (coalesce(filters->>'code','')='' or strpos(lower(r.code),lower(filters->>'code'))>0)
   and (coalesce(filters->>'item_name','')='' or strpos(lower(r.item_name),lower(filters->>'item_name'))>0)
   and (coalesce(filters->>'requested_by_name','')='' or strpos(lower(r.requested_by_name),lower(filters->>'requested_by_name'))>0))
  select (select coalesce(jsonb_agg(to_jsonb(x)),'[]') from (select * from data order by created_at desc,id limit 50 offset (page-1)*50)x),(select count(*) from data) into rows_data,total;
  if selected is not null then
   select to_jsonb(r)||jsonb_build_object('supplier_name',(select name from public.suppliers where factory_id=factory and id=r.supplier_id),'history',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.purchase_request_events e where e.factory_id=factory and e.request_id=r.id)) into details
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
revoke all on function public.supply_page(uuid,text,integer,jsonb,uuid) from public,anon;
grant execute on function public.supply_page(uuid,text,integer,jsonb,uuid) to authenticated;
