-- Isolated regression; all temporary grants and Audit rows roll back.
begin;
create function pg_temp.export_assert(ok boolean,label text) returns void language plpgsql as $$begin if ok is distinct from true then raise exception 'Export: %',label;end if;end$$;
create function pg_temp.export_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=expected then return;end if;raise exception 'Export expected %, got %',expected,sqlerrm;end;
 raise exception 'Export expected % but succeeded',expected;
end$$;
do $$declare f uuid;actor uuid;item jsonb;row jsonb;name text;count_rows bigint;begin
 select m.factory_id,m.user_id into f,actor from public.memberships m join public.factories fac on fac.id=m.factory_id where fac.is_demo and not m.is_owner and m.status='approved' order by m.created_at,m.id limit 1;
 perform pg_temp.export_assert(actor is not null,'non-owner fixture');
 delete from public.member_permission_packages where factory_id=f and user_id=actor;
 insert into public.user_permissions(factory_id,user_id,module,action)select f,actor,module,action from public.permissions on conflict do nothing;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 execute 'set local role authenticated';
 foreach name in array array['bom_versions','bom_items','sales_orders','sales_order_lines','finished_goods_reservations','sales_incoming_allocations','finished_goods_movements','production_receipt_acknowledgments','material_requests','purchase_requisitions','purchase_request_events','suppliers','supplier_categories','supplier_category_links'] loop
  item:=public.factory_export_page(f,name,1);
  perform pg_temp.export_assert(jsonb_typeof(item->'rows')='array' and (item->>'total')::bigint>=jsonb_array_length(item->'rows'),'bounded reader '||name);
  for row in select value from jsonb_array_elements(item->'rows') loop
   perform pg_temp.export_assert(row->>'factory_id'=f::text,'scope '||name);
   perform pg_temp.export_assert(not(row ?| array['password','encrypted_password','token','secret','old_data','new_data']),'safe fields '||name);
  end loop;
 end loop;
 perform pg_temp.export_error('select * from public.bom_versions','permission denied for table bom_versions');
 perform pg_temp.export_error(format('select public.factory_export_page(%L,''auth.users'',1)',f),'export_invalid');
 perform pg_temp.export_error(format('select public.factory_export_page(%L,''suppliers'',0)',f),'export_invalid');
 perform pg_temp.export_error(format('select public.factory_export_page(%L,''suppliers'',201)',f),'export_invalid');
 perform pg_temp.export_error('select public.factory_export_page(''10000000-0000-0000-0000-000000000001'',''suppliers'',1)','permission_denied');
 execute 'reset role';
 delete from public.user_permissions where factory_id=f and user_id=actor and module='factory' and action='export';
 perform pg_temp.export_error(format('select public.factory_export_page(%L,''suppliers'',1)',f),'permission_denied');
 insert into public.user_permissions(factory_id,user_id,module,action)values(f,actor,'factory','export');
 delete from public.user_permissions where factory_id=f and user_id=actor and module='purchasing' and action='view';
 perform pg_temp.export_error(format('select public.factory_export_page(%L,''bom_versions'',1)',f),'permission_denied');
 set constraints all immediate;
end$$;
select 'Export reader: all 14 datasets, scope, fixed fields, page bounds, direct-read denial and revoked/missing grants passed' as result;
rollback;
