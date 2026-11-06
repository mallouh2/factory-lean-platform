-- Read-only stock explanation. No ledger, reservation, allocation or gate writes.
begin;
create function public.warehouse_inventory_context(factory uuid,item uuid,item_type text,unit text,page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare stock jsonb;reservations jsonb;shown jsonb;recent jsonb;known numeric;delta numeric;total integer;pages integer;actual_page integer;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');
 if page is null or page<1 or page>1000000 or item_type is null or item_type not in ('finished','material') then raise exception 'fulfillment_invalid';end if;
 select r into stock from private.warehouse_inventory_rows(factory) r where r->>'id'=item::text and r->>'entity'=item_type;
 if stock is null then raise exception 'permission_denied' using errcode='42501';end if;
 if unit is distinct from stock->>'unit' then raise exception 'fulfillment_stock_identity';end if;
 if item_type='finished' then
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'quantity',trim_scale(r.quantity)::text,'kind','SALES','order_id',so.id,'reference',so.code,'status',so.status,'purpose','SALES_FULFILLMENT',
   'sources',(select coalesce(jsonb_agg(jsonb_build_object('label',s.physical_label,'quantity',trim_scale(sr.quantity)::text)),'[]') from public.finished_goods_source_reservations sr join public.finished_goods_sources s on s.factory_id=sr.factory_id and s.id=sr.source_id where sr.factory_id=factory and sr.sales_line_id=sl.id)) order by so.created_at,so.id,r.id),'[]'),coalesce(sum(r.quantity),0)
   into reservations,known from public.finished_goods_reservations r join public.sales_order_lines sl on sl.factory_id=r.factory_id and sl.id=r.line_id join public.sales_orders so on so.factory_id=sl.factory_id and so.id=sl.order_id
   where r.factory_id=factory and sl.product_id=item and sl.unit=warehouse_inventory_context.unit and r.quantity>0;
 else
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'quantity',trim_scale(r.quantity)::text,'kind',case when o.id is null then 'MATERIAL' else 'PRODUCTION' end,'order_id',o.id,'reference',o.code,'status','ACTIVE','purpose','MATERIAL_ALLOCATION','sources','[]'::jsonb) order by o.code nulls last,r.id),'[]'),coalesce(sum(r.quantity),0)
   into reservations,known from public.inventory_reservations r left join public.production_orders o on o.factory_id=r.factory_id and o.id=r.order_id
   where r.factory_id=factory and r.material_id=item and r.released_at is null;
 end if;
 if unit is null then reservations:='[]';known:=null;end if;
 delta:=(stock->>'reserved')::numeric-known;
 -- Explain an actual balance not attributable to an order; never invent its owner.
 if delta>0 then reservations:=reservations||jsonb_build_array(jsonb_build_object('id',null,'quantity',trim_scale(delta)::text,'kind','UNATTRIBUTED','order_id',null,'reference',null,'status','RECORDED_BALANCE','purpose','UNATTRIBUTED_BALANCE','sources','[]'::jsonb));end if;
 total:=jsonb_array_length(reservations);pages:=greatest(1,(total+49)/50);actual_page:=least(page,pages);
 select coalesce(jsonb_agg(value order by ord),'[]') into shown from (select value,ord from jsonb_array_elements(reservations) with ordinality a(value,ord) order by ord limit 50 offset (actual_page-1)*50)x;
 select coalesce(jsonb_agg(value||jsonb_build_object('order_reference',case when item_type='finished' then (select coalesce(po.code,so.code) from public.finished_goods_movements m left join public.production_entries e on e.factory_id=m.factory_id and e.id=m.entry_id left join public.production_orders po on po.factory_id=e.factory_id and po.id=e.order_id left join public.sales_order_lines sl on sl.factory_id=m.factory_id and sl.id=m.sales_line_id left join public.sales_orders so on so.factory_id=sl.factory_id and so.id=sl.order_id where m.factory_id=factory and m.id=(value->>'id')::uuid) else value->>'reference' end) order by ord),'[]') into recent
  from (select value,ord from jsonb_array_elements(public.warehouse_movements(factory,item,item_type,1)->'rows') with ordinality a(value,ord) where unit is null or value->>'unit'=warehouse_inventory_context.unit order by ord limit 5)x;
 return jsonb_build_object('summary',jsonb_build_object('on_hand',stock->>'on_hand','reserved',stock->>'reserved','available',stock->>'available','projected',stock->>'projected','unit',unit),
  'rows',shown,'total',total,'page',actual_page,'pages',pages,'page_size',50,'known_reserved',known::text,'unattributed_reserved',case when delta>0 then delta::text else '0' end,'reconciled',case when delta is null then null else delta>=0 end,'difference',delta::text,'recent',recent);
end$$;
create function public.warehouse_reservation_order(factory uuid,target uuid,kind text) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');
 if kind='SALES' then
  perform private.require_permission(factory,'sales_orders','view');
  result:=private.sales_order_detail(factory,target);
 elsif kind='PRODUCTION' then
  perform private.require_permission(factory,'orders','view');
  select jsonb_build_object('id',o.id,'code',o.code,'status',o.status,'product_name',p.name,'product_name_ar',p.name_ar,'quantity',o.target_quantity::text,'unit',o.unit)
   into result from public.production_orders o join public.products p on p.factory_id=o.factory_id and p.id=o.product_id where o.factory_id=factory and o.id=target;
 else raise exception 'fulfillment_invalid';end if;
 if result is null then raise exception 'permission_denied' using errcode='42501';end if;return result;
end$$;
revoke all on function public.warehouse_inventory_context(uuid,uuid,text,text,integer),public.warehouse_reservation_order(uuid,uuid,text) from public,anon,service_role;
grant execute on function public.warehouse_inventory_context(uuid,uuid,text,text,integer),public.warehouse_reservation_order(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
commit;
