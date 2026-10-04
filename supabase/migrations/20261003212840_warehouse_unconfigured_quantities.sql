-- Unknown primary-unit quantities remain NULL; typed zero stock remains zero.
create or replace function private.warehouse_inventory_rows(f uuid) returns setof jsonb
language sql stable security definer set search_path='' as $$
 with all_projection as materialized(select * from private.finished_inventory_projection(f)),
 unit_keys as (select product_id,unit from all_projection where unit is not null union select o.product_id,e.unit from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and l.quantity_available>0),
 product_units as (select p.id,coalesce(p.stock_unit,case when count(distinct x.unit)=1 then min(x.unit) end) unit
  from public.products p left join unit_keys x on x.product_id=p.id where p.factory_id=f and p.stage='finished' group by p.id),
 base as (
 select p.id,'finished'::text entity,p.name,p.name_ar,p.code,case when p.product_kind='MANUFACTURED_INTERMEDIATE' then 'MANUFACTURED_INTERMEDIATE' else 'FINISHED_GOOD' end item_type,p.supply_source,k.unit,
 case when k.unit is not null then coalesce(x.on_hand,0) end on_hand,case when k.unit is not null then coalesce(x.reserved,0) end reserved,case when k.unit is not null then coalesce(x.on_hand-x.reserved,0) end available,
 case when k.unit is not null then coalesce(x.incoming,0)-coalesce((select sum(o.remaining_quantity) from public.production_orders o where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status='active' and o.actual_start is not null and o.actual_finish is null),0)+private.purchase_incoming(f,p.id,k.unit) end incoming,
 case when k.unit is not null then coalesce(x.projected,0)+private.purchase_incoming(f,p.id,k.unit) end projected,case when k.unit=p.stock_unit then p.minimum_stock end minimum_stock,case when k.unit=p.stock_unit then p.maximum_stock end maximum_stock,
 case when k.unit is not null then coalesce((select sum(l.warehouse_quantity) from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and o.product_id=p.id and e.unit=k.unit),0) end semi_finished,
 case when k.unit is not null then coalesce((select sum(o.remaining_quantity) from public.production_orders o where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status='active' and o.actual_start is not null and o.actual_finish is null),0) end in_production,
 exists(select 1 from public.production_orders o join public.production_requests r on r.id=o.request_id where o.factory_id=f and o.product_id=p.id and o.unit=k.unit and o.status in ('planned','active') and r.request_type='STOCK_REPLENISHMENT') already_requested,
 exists(select 1 from public.purchase_requisitions pr where pr.factory_id=f and pr.product_id=p.id and pr.unit=k.unit and pr.status not in ('RECEIVED','REJECTED','CANCELLED')) purchase_requested,
 (select coalesce(jsonb_agg(coalesce(to_jsonb(z),jsonb_build_object('on_hand',0,'reserved',0,'available',0,'incoming',0,'projected',0))||jsonb_build_object('unit',uk.unit,'semi_finished',coalesce((select sum(l.warehouse_quantity) from public.unfinished_lots l join public.production_entries e on e.id=l.source_entry_id join public.production_orders o on o.id=e.order_id where l.factory_id=f and o.product_id=p.id and e.unit=uk.unit),0))),'[]') from unit_keys uk left join all_projection z on z.product_id=uk.product_id and z.unit=uk.unit where uk.product_id=p.id) unit_breakdown
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
