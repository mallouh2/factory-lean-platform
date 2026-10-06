-- Bounded application export of datasets that intentionally expose no direct SELECT.
-- Preserve their existing RLS/no-direct-write boundaries; callers must hold export and every included view grant.
begin;
create function public.factory_export_page(factory uuid,dataset text,page integer default 1) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare columns_sql text;order_sql text;total bigint;rows jsonb;module text;
begin
 perform private.require_permission(factory,'factory','export');
 foreach module in array array['factory','employees','roles','lines','centers','orders','sales_orders','warehouse','purchasing','downtime','maintenance','lean','audit'] loop perform private.require_permission(factory,module,'view');end loop;
 if page is null or page not between 1 and 200 then raise exception 'export_invalid' using errcode='22023';end if;
 case dataset
 when 'bom_versions' then columns_sql:='factory_id,id,product_id,version,batch_quantity,output_unit,created_at';order_sql:='id';
 when 'bom_items' then columns_sql:='factory_id,id,bom_id,material_id,quantity,unit,waste_allowance';order_sql:='id';
 when 'sales_orders' then columns_sql:='factory_id,id,code,customer_reference,status,requested_by,requested_delivery,promised_delivery,safety_buffer_days,notes,approved_at,approved_by,created_at';order_sql:='id';
 when 'sales_order_lines' then columns_sql:='factory_id,id,order_id,product_id,quantity,unit,release_when_ready,dispatched_quantity';order_sql:='id';
 when 'finished_goods_reservations' then columns_sql:='factory_id,id,line_id,quantity';order_sql:='id';
 when 'sales_incoming_allocations' then columns_sql:='factory_id,id,line_id,item_id,quantity,received_quantity,released_quantity,created_at';order_sql:='id';
 when 'finished_goods_movements' then columns_sql:='factory_id,id,product_id,unit,kind,stock_delta,reserved_delta,sales_line_id,entry_id,reason,external_reference,created_at,created_by';order_sql:='id';
 when 'production_receipt_acknowledgments' then columns_sql:='factory_id,entry_id,received_by,received_at';order_sql:='entry_id';
 when 'material_requests' then columns_sql:='factory_id,id,item_name,material_id,product_id,lot_id,production_item_id,quantity,unit,status,note,requested_by_name,created_at,issued_by,issued_at,received_by,received_at,movement_id,reason';order_sql:='id';
 when 'purchase_requisitions' then columns_sql:='factory_id,id,code,item_name,material_id,product_id,quantity,unit,details,notes,status,source_context,requested_by_name,created_at,supplier_id,supplier_text,purchasing_note,received_by,received_at,receipt_movement_id';order_sql:='id';
 when 'purchase_request_events' then columns_sql:='factory_id,id,request_id,status,note,supplier_name,actor_name,created_at';order_sql:='id';
 when 'suppliers' then columns_sql:='factory_id,id,name,primary_contact,phone,email,notes,active,created_at';order_sql:='id';
 when 'supplier_categories' then columns_sql:='factory_id,id,name';order_sql:='id';
 when 'supplier_category_links' then columns_sql:='factory_id,supplier_id,category_id,relationship';order_sql:='supplier_id,category_id';
 else raise exception 'export_invalid' using errcode='22023';end case;
 execute format('select count(*) from public.%I where factory_id=$1',dataset) into total using factory;
 if total>100000 then raise exception 'export_too_large' using errcode='54000';end if;
 execute format('select coalesce(jsonb_agg(to_jsonb(x)),''[]''::jsonb) from (select %s from public.%I where factory_id=$1 order by %s limit 500 offset $2)x',columns_sql,dataset,order_sql) into rows using factory,(page-1)*500;
 return jsonb_build_object('rows',rows,'total',total);
end$$;
revoke all on function public.factory_export_page(uuid,text,integer) from public,anon;
grant execute on function public.factory_export_page(uuid,text,integer) to authenticated;
comment on function public.factory_export_page(uuid,text,integer) is 'Factory-scoped export only. Fixed datasets/columns; existing export plus all workflow view grants; no direct table privileges.';
commit;
