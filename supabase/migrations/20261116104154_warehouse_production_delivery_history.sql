-- Read-only retained delivery requests for Warehouse Completed / All filters.
-- Existing active reader, permissions, physical stock, events and accounting unchanged.
CREATE OR REPLACE FUNCTION public.production_stock_request_history(factory uuid, page integer DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare rows jsonb;total bigint;begin
 perform private.require_permission(factory,'factory','view');perform private.require_permission(factory,'warehouse','view');
 if page is null or page not between 1 and 10000 then raise exception 'material_invalid'using errcode='22023';end if;
 select count(*)into total from private.production_supply_requests h where h.factory_id=factory;
 select coalesce(jsonb_agg(x order by x->>'created_at',x->>'id'),'[]')into rows from(
 select to_jsonb(h)||jsonb_build_object('rows',(select jsonb_agg(to_jsonb(r)||jsonb_build_object('name',m.name,'name_ar',m.name_ar,'quantity',trim_scale(r.quantity)::text,'delivered',trim_scale(r.delivered)::text)order by m.name)
 from private.production_supply_rows r join public.materials m on m.factory_id=r.factory_id and m.id=r.material_id where r.factory_id=factory and r.request_id=h.id))x
 from private.production_supply_requests h where h.factory_id=factory
 order by h.created_at,h.id limit 50 offset(page-1)*50)t;
 return jsonb_build_object('rows',rows,'total',total);end$function$;
revoke all on function public.production_stock_request_history(uuid,integer)from public,anon;
grant execute on function public.production_stock_request_history(uuid,integer)to authenticated,service_role;
