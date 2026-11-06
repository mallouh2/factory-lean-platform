-- Read-only History detail: one product across all items in the same request.
begin;
create function public.production_history_product_scrap(factory uuid, entry uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
 perform private.require_permission(factory,'orders','view');
 with selected as (
   select o.request_id,o.product_id from public.production_entries e
   join public.production_orders o on o.id=e.order_id and o.factory_id=e.factory_id
   where e.factory_id=factory and e.id=entry
 ), quantities as (
   select e.effective_scrap_kg from selected s
   join public.production_orders o on o.factory_id=factory and o.request_id=s.request_id and o.product_id=s.product_id
   join public.production_entries e on e.factory_id=o.factory_id and e.order_id=o.id
 )
 select jsonb_build_object('scrap_kg',case when count(*)>0 and count(effective_scrap_kg)=count(*)
   and bool_and(effective_scrap_kg>=0) then sum(effective_scrap_kg)::text else null end)
 into result from quantities;
 return result;
end$$;
revoke all on function public.production_history_product_scrap(uuid,uuid) from public,anon;
grant execute on function public.production_history_product_scrap(uuid,uuid) to authenticated;
comment on function public.production_history_product_scrap(uuid,uuid) is
 'Official effective Scrap KG, exact text; factory/request/product scoped, independent of History pagination. Missing evidence remains null.';
notify pgrst,'reload schema';
commit;
