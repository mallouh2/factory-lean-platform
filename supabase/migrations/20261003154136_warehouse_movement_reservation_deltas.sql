-- Show physical and reserved deltas separately; reservations are not physical receipts.
create or replace function public.warehouse_movements(factory uuid,item uuid,item_type text,page integer default 1) returns jsonb language plpgsql stable security definer set search_path='' as $$declare rows jsonb;total integer;begin
 perform private.require_permission(factory,'warehouse','view');if page is null or page not between 1 and 1000000 then raise exception 'fulfillment_invalid';end if;
 if item_type='finished' then
  select count(*) into total from public.finished_goods_movements where factory_id=factory and product_id=item;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=factory and user_id=x.created_by))),'[]') into rows from(select id,kind,stock_delta quantity,reserved_delta,unit,reason note,external_reference reference,created_by,created_at from public.finished_goods_movements where factory_id=factory and product_id=item order by created_at desc,id limit 25 offset (page-1)*25)x;
 elsif item_type='material' then
  select count(*) into total from public.inventory_transactions where factory_id=factory and material_id=item;
  select coalesce(jsonb_agg(to_jsonb(x)||jsonb_build_object('actor_name',(select display_name from public.memberships where factory_id=factory and user_id=x.created_by))),'[]') into rows from(select id,kind,quantity,unit,note,reference,created_by,created_at from public.inventory_transactions where factory_id=factory and material_id=item order by created_at desc,id limit 25 offset (page-1)*25)x;
 else raise exception 'fulfillment_invalid';end if;return jsonb_build_object('rows',rows,'total',total);end$$;
