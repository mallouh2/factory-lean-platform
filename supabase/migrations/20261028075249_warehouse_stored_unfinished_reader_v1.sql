begin;
create function public.warehouse_stored_unfinished(factory uuid,page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$declare result jsonb;begin
 perform private.require_permission(factory,'warehouse','view');
 if page not between 1 and 1000000 then raise exception 'invalid_input';end if;
 with lots as materialized(
 select p.id product_id,p.name,p.name_ar,e.unit,l.remaining_work,l.warehouse_quantity,
 case when l.reserved_quality_rejection_id is not null then l.warehouse_quantity else a.reserved end reserved,
 private.output_source_held(factory,l.source_entry_id) held
 from public.unfinished_lots l join public.production_entries e on e.factory_id=factory and e.id=l.source_entry_id
 join public.production_orders o on o.factory_id=factory and o.id=e.order_id
 join public.products p on p.factory_id=factory and p.id=o.product_id
 cross join lateral private.output_work_allocations(factory,l.id) a
 where l.factory_id=factory and l.warehouse_quantity>0), grouped as(
 select product_id,name,name_ar,unit,remaining_work,sum(warehouse_quantity) on_hand,sum(reserved) reserved,
 sum(case when held then 0 else warehouse_quantity-reserved end) available,bool_or(held) held
 from lots group by product_id,name,name_ar,unit,remaining_work)
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r))from(
 select product_id,name,name_ar,unit,remaining_work,trim_scale(on_hand)::text on_hand,trim_scale(reserved)::text reserved,trim_scale(available)::text available,held
 from grouped order by name,product_id,unit,remaining_work offset (page-1)*50 limit 50)r),'[]'::jsonb),'total',(select count(*)from grouped))into result;
 return result;
end$$;
revoke all on function public.warehouse_stored_unfinished(uuid,integer) from public,anon,authenticated,service_role;
grant execute on function public.warehouse_stored_unfinished(uuid,integer) to authenticated;
commit;
