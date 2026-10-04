-- TESTING only; all fixtures, permission changes and movements roll back.
begin;
create temporary table warehouse_purchase_checks(label text);
create function pg_temp.check_purchase(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Warehouse purchase: %',label;end if;
 insert into warehouse_purchase_checks values(label);
end$$;
create function pg_temp.purchase_error(statement text,expected text,label text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm<>expected then raise exception 'Warehouse purchase %: expected %, got %',label,expected,sqlerrm;end if;
  insert into warehouse_purchase_checks values(label);return;
 end;raise exception 'Warehouse purchase %: expected failure',label;
end$$;
create function pg_temp.purchase_call(f uuid,a text,p jsonb) returns uuid language sql as $$select public.supply_command(f,a,p,gen_random_uuid())$$;
create function pg_temp.purchase_change(f uuid,r uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.purchase_call(f,'purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action',a,'reason',reason));
$$;
do $test$
declare f uuid;actor uuid;raw uuid;acc uuid;pack uuid;compound uuid;product uuid;unconfigured uuid;r uuid;r2 uuid;token uuid;p jsonb;supplier uuid;before_orders bigint;item uuid;
begin
 select m.factory_id,m.user_id into f,actor from public.memberships m join public.factories fac on fac.id=m.factory_id where fac.is_demo and m.is_owner and m.status='approved' limit 1;
 if actor is null then raise exception 'Existing TESTING actor required';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 -- The signed-in platform account can have a temporary support scope; isolate normal person grants in this rollback fixture.
 update private.platform_scopes set expires_at=now() where user_id=actor and factory_id=f;
 insert into public.user_permissions(factory_id,user_id,module,action) select f,actor,module,action from public.permissions where module in ('warehouse','purchasing','suppliers') on conflict do nothing;
 raw:=public.create_warehouse_material(f,jsonb_build_object('name','Warehouse manual QA raw','code','UX-'||gen_random_uuid(),'unit','kg','inventory_kind','RAW_MATERIAL'),gen_random_uuid());
 acc:=public.create_warehouse_material(f,jsonb_build_object('name','Warehouse manual QA accessory','code','UX-'||gen_random_uuid(),'unit','piece','inventory_kind','ACCESSORY'),gen_random_uuid());
 pack:=public.create_warehouse_material(f,jsonb_build_object('name','Warehouse manual QA packaging','code','UX-'||gen_random_uuid(),'unit','piece','inventory_kind','PACKAGING'),gen_random_uuid());
 compound:=public.define_manufactured_product(f,null,jsonb_build_object('name','Warehouse manual QA compound','code','UX-'||gen_random_uuid(),'unit','kg','stock_unit','kg','product_kind','MANUFACTURED_INTERMEDIATE'),null,gen_random_uuid());
 product:=public.define_manufactured_product(f,null,jsonb_build_object('name','Warehouse manual QA pipe','code','UX-'||gen_random_uuid(),'unit','piece','stock_unit','piece'),null,gen_random_uuid());
 unconfigured:=public.define_manufactured_product(f,null,jsonb_build_object('name','Warehouse manual QA unconfigured','code','UX-'||gen_random_uuid(),'unit','piece'),null,gen_random_uuid());
 update public.products set stock_unit=null where id=unconfigured;
 select count(*) into before_orders from public.production_orders where factory_id=f;
 p:=jsonb_build_object('item',raw,'quantity',7,'unit','kg','details','');token:=gen_random_uuid();
 r:=public.supply_command(f,'purchase_inventory',p,token);
 perform pg_temp.check_purchase((select material_id=raw and product_id is null and details='' and notes='' and quantity=7 and unit='kg' and source_context='Warehouse' and requested_by=actor and requested_by_name<>'' and status='REQUESTED' from public.purchase_requisitions where id=r),'known raw item, optional empty Details, no Notes, server actor and context');
 perform pg_temp.check_purchase(public.supply_command(f,'purchase_inventory',p,token)=r,'same retry returns same request');
 perform pg_temp.check_purchase((select count(*)=1 from public.purchase_request_events where request_id=r),'retry creates only one history event');
 perform pg_temp.purchase_error(format('select public.supply_command(%L,%L,%L::jsonb,%L)',f,'purchase_inventory',p||'{"quantity":8}',token),'request_conflict','changed retry payload rejected');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_inventory',p),'supply_duplicate','new retry cannot duplicate active stock request');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_inventory',p||'{"unit":"piece"}'),'supply_invalid','configured kg cannot silently become pieces');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_stock',jsonb_build_object('item',product,'quantity',1,'unit','piece','projected',0)),'supply_invalid','Min/Max manufactured purchase guard unchanged');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_stock',p||'{"projected":0}'),'supply_invalid','Min/Max payload contract remains narrow');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_stock',jsonb_build_object('item',acc,'quantity',1,'unit','piece','projected',0)),'warehouse_stock_changed','Min/Max still requires low-stock preview');
 foreach item in array array[acc,pack,compound,product] loop
  r2:=pg_temp.purchase_call(f,'purchase_inventory',jsonb_build_object('item',item,'quantity',2,'unit',case when item=compound then 'kg' else 'piece' end));
  perform pg_temp.check_purchase((select coalesce(material_id,product_id)=item and details='' from public.purchase_requisitions where id=r2),'existing inventory kind stock link '||item);
 end loop;
 perform pg_temp.check_purchase((select supply_source='MANUFACTURED' from public.products where id=product),'manual external purchase preserves manufacturing source');
 perform pg_temp.check_purchase((select count(*)=before_orders from public.production_orders where factory_id=f),'manual purchasing creates no Production');
 r2:=pg_temp.purchase_call(f,'purchase_inventory',jsonb_build_object('item',unconfigured,'quantity',2));
 perform pg_temp.check_purchase((select unit='piece' from public.purchase_requisitions where id=r2),'Piece default when no configured stock unit');
 perform pg_temp.purchase_change(f,r2,'CANCELLED','QA unit selection');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_inventory',jsonb_build_object('item',unconfigured,'quantity',2,'unit','kg')),'supply_invalid','ordinary finished Product cannot promise compound-only kg stock');
 r2:=pg_temp.purchase_call(f,'purchase_inventory',jsonb_build_object('item',unconfigured,'quantity',2,'unit','meter'));
 perform pg_temp.check_purchase((select unit='meter' and product_id=unconfigured from public.purchase_requisitions where id=r2),'valid explicit unit preserved without creating definition');
 supplier:=pg_temp.purchase_call(f,'supplier_save',jsonb_build_object('name','Warehouse unconfigured QA supplier'));
 perform pg_temp.purchase_call(f,'purchase_change',jsonb_build_object('id',r2,'revision',(select revision from public.purchase_requisitions where id=r2),'action','supplier','supplier_id',supplier));
 perform pg_temp.purchase_change(f,r2,'UNDER_REVIEW');perform pg_temp.purchase_change(f,r2,'ORDERED');perform pg_temp.purchase_change(f,r2,'READY_FOR_RECEIPT');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'receive_purchase',jsonb_build_object('id',r2,'revision',(select revision from public.purchase_requisitions where id=r2))),'fulfillment_stock_identity','unconfigured Product purchase cannot invent received stock');
 perform public.configure_warehouse_product(f,unconfigured,'MANUFACTURED','MAKE_TO_ORDER','meter',null,null);
 perform pg_temp.purchase_call(f,'receive_purchase',jsonb_build_object('id',r2,'revision',(select revision from public.purchase_requisitions where id=r2)));
 perform pg_temp.check_purchase((select sum(stock_delta)=2 from public.finished_goods_movements where product_id=unconfigured and unit='meter'),'matching Stock Settings unlock legitimate External Receipt');
 foreach p in array array[jsonb_build_object('item',gen_random_uuid(),'quantity',1,'unit','kg'),jsonb_build_object('item',raw,'quantity',0,'unit','kg'),jsonb_build_object('item',raw,'quantity','NaN','unit','kg'),jsonb_build_object('item',raw,'quantity',1,'unit','kg','requested_by',actor),jsonb_build_object('item',raw,'quantity',1,'unit','kg','notes','extra')] loop
  perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_inventory',p),'supply_invalid','invalid identity/quantity/actor/Notes rejected');
 end loop;
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_manual','{"item_name":"Direct spare","quantity":1,"unit":"piece","details":"","source_context":"Maintenance"}'),'supply_invalid','free-text specification remains mandatory');
 supplier:=pg_temp.purchase_call(f,'supplier_save',jsonb_build_object('name','Warehouse manual QA supplier'));
 perform pg_temp.purchase_call(f,'purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier','supplier_id',supplier));
 perform pg_temp.purchase_change(f,r,'UNDER_REVIEW');perform pg_temp.purchase_change(f,r,'ORDERED');
 perform pg_temp.check_purchase((select (value->>'incoming')::numeric=7 from private.warehouse_inventory_rows(f) value where value->>'id'=raw::text),'Ordered manual stock purchase contributes authoritative incoming');
 perform pg_temp.purchase_change(f,r,'READY_FOR_RECEIPT');
 p:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r));token:=gen_random_uuid();
 perform public.supply_command(f,'receive_purchase',p,token);perform public.supply_command(f,'receive_purchase',p,token);
 perform pg_temp.check_purchase((select status='RECEIVED' and received_by=actor and receipt_movement_id is not null from public.purchase_requisitions where id=r),'existing Purchasing and External Receipt finish linked request');
 perform pg_temp.check_purchase((select sum(quantity)=7 and count(*)=1 from public.inventory_transactions where material_id=raw),'stock receipt credits exactly once');
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'receive_purchase',p),'supply_conflict','fresh duplicate receipt rejected');
 delete from public.user_permissions where factory_id=f and user_id=actor and module='warehouse' and action='edit';
 perform pg_temp.purchase_error(format('select pg_temp.purchase_call(%L,%L,%L::jsonb)',f,'purchase_inventory',jsonb_build_object('item',raw,'quantity',1,'unit','kg')),'permission_denied','owner/Purchasing title without Warehouse edit cannot create');
 perform pg_temp.purchase_error(format('select public.supply_command(%L,%L,%L::jsonb,%L)',f,'purchase_inventory',jsonb_build_object('item',raw,'quantity',7,'unit','kg','details',''),(select request_id from public.fulfillment_commands where result_id=r and operation='supply_purchase_inventory')),'permission_denied','permission required before retry read');
 perform pg_temp.check_purchase(not has_function_privilege('authenticated','private.warehouse_inventory_purchase(uuid,jsonb,uuid)','execute'),'private helper cannot bypass public contract');
 perform pg_temp.check_purchase(not has_function_privilege('anon','public.supply_command(uuid,text,jsonb,uuid)','execute'),'anonymous supply mutations denied');
 set constraints all immediate;
end$test$;
select format('Warehouse manual inventory purchases: %s assertions passed; all fixtures rolled back',count(*)) result from warehouse_purchase_checks;
rollback;
