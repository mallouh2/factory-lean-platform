-- Requests needs the existing dispatch order source, not Inventory projections.
begin;
create function public.warehouse_dispatch_requests_page(factory uuid,page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare orders jsonb;begin
 perform private.require_permission(factory,'warehouse','view');
 if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid' using errcode='22023';end if;
 select coalesce(jsonb_agg(private.sales_order_detail(factory,id) order by created_at,id),'[]') into orders
 from(select id,created_at from public.sales_orders where factory_id=factory and status='approved' order by created_at,id limit 25 offset (page-1)*25)s;
 return jsonb_build_object('orders',orders,'orders_total',(select count(*) from public.sales_orders where factory_id=factory and status='approved'),'page',page,'page_size',25);
end$$;
revoke all on function public.warehouse_dispatch_requests_page(uuid,integer) from public,anon;
grant execute on function public.warehouse_dispatch_requests_page(uuid,integer) to authenticated;
notify pgrst,'reload schema';
commit;
