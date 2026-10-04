-- TESTING only; existing people, fixtures and support-scope isolation roll back.
begin;
create temporary table requester_checks(label text);
create function pg_temp.qcheck(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Requester: %',label;end if;
 insert into requester_checks values(label);
end$$;
create function pg_temp.qerror(statement text,expected text,label text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm<>expected then raise exception 'Requester % expected %, got %',label,expected,sqlerrm;end if;
  insert into requester_checks values(label);return;
 end;raise exception 'Requester % expected failure',label;
end$$;
create function pg_temp.qcall(f uuid,a text,p jsonb) returns uuid language sql as $$select public.supply_command(f,a,p,gen_random_uuid())$$;
create function pg_temp.qchange(f uuid,r uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.qcall(f,'purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action',a,'reason',reason));
$$;
do $test$
declare f uuid;actor uuid;other uuid;r uuid;direct uuid;stock uuid;raw uuid;supplier uuid;token uuid;p jsonb;x jsonb;context text;state text;
 definitions bigint;movements bigint;events bigint;
begin
 select m.factory_id,m.user_id into f,actor from public.memberships m join public.factories fac on fac.id=m.factory_id where fac.is_demo and m.is_owner and m.status='approved' limit 1;
 select user_id into other from public.memberships where factory_id=f and user_id<>actor and status='approved' limit 1;
 if actor is null or other is null then raise exception 'Existing TESTING people required';end if;
 update private.platform_scopes set expires_at=now() where factory_id=f and user_id in (actor,other);
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.user_permissions(factory_id,user_id,module,action) select f,actor,module,action from public.permissions where module in ('warehouse','purchasing','suppliers') on conflict do nothing;
 insert into public.user_permissions values(f,other,'factory','view') on conflict do nothing;
 raw:=public.create_warehouse_material(f,jsonb_build_object('name','PVC requester QA resin','name_ar','راتنج اختبار المشتريات','code','RQS-'||gen_random_uuid(),'unit','kg','inventory_kind','RAW_MATERIAL'),gen_random_uuid());
 supplier:=pg_temp.qcall(f,'supplier_save',jsonb_build_object('name','Requester QA supplier'));
 select (select count(*) from public.materials)+(select count(*) from public.products) into definitions;
 select (select count(*) from public.inventory_transactions)+(select count(*) from public.finished_goods_movements) into movements;
 p:=jsonb_build_object('item','other','quantity',4,'unit','piece','details','SKF 6205-2RS bearing');token:=gen_random_uuid();
 direct:=public.supply_command(f,'purchase_inventory',p,token);
 perform pg_temp.qcheck((select material_id is null and product_id is null and details='SKF 6205-2RS bearing' and item_name='SKF 6205-2RS bearing' and notes='' and unit='piece' and source_context='Warehouse' and requested_by=actor from public.purchase_requisitions where id=direct),'Other uses required Details as non-stock identity without a second name field');
 perform pg_temp.qcheck(public.supply_command(f,'purchase_inventory',p,token)=direct,'Other retry idempotent');
 perform pg_temp.qcheck((select count(*)=1 from public.purchase_request_events where request_id=direct),'Other retry history once');
 perform pg_temp.qcheck((select (select count(*) from public.materials)+(select count(*) from public.products))=definitions,'Other creates no catalogue definition');
 perform pg_temp.qcheck((select (select count(*) from public.inventory_transactions)+(select count(*) from public.finished_goods_movements))=movements,'Other creation creates no stock');
 foreach p in array array[jsonb_build_object('item','other','quantity',4,'unit','piece','details',''),jsonb_build_object('item','other','quantity',0,'unit','piece','details','Bearing'),jsonb_build_object('item','other','quantity','NaN','unit','piece','details','Bearing'),jsonb_build_object('item','other','quantity',4,'unit','forged','details','Bearing'),jsonb_build_object('item','other','quantity',4,'unit','kg','details','Bearing','status','ORDERED')] loop
  perform pg_temp.qerror(format('select pg_temp.qcall(%L,%L,%L::jsonb)',f,'purchase_inventory',p),'supply_invalid','Other specification/positive finite qty/unit/forged status denied');
 end loop;
 r:=pg_temp.qcall(f,'purchase_inventory',jsonb_build_object('item','other','quantity',1,'unit','kg','details','Direct kg spare'));
 perform pg_temp.qcheck((select unit='kg' and material_id is null and product_id is null from public.purchase_requisitions where id=r),'Other legitimate kg choice retained');
 foreach state in array array['PVC requester QA','راتنج اختبار',(select code from public.materials where id=raw)] loop
  x:=public.supply_page(f,'catalogue',1,jsonb_build_object('search',state));
  perform pg_temp.qcheck(exists(select 1 from jsonb_array_elements(x->'rows') v where v->>'id'=raw::text),'catalogue searches existing names Arabic and codes');
 end loop;
 perform pg_temp.qcheck(public.supply_page(f,'stock_purchases',1,'{}',direct)->'selected' is not null and public.supply_page(f,'stock_purchases',1,'{}',direct)->'selected'<>'null'::jsonb,'Warehouse sees own Other request');
 foreach context in array array['Warehouse','Production','Maintenance','Administration'] loop
  r:=pg_temp.qcall(f,'purchase_manual',jsonb_build_object('item_name',context||' direct part','quantity',1,'unit','piece','details','Exact specification','source_context',context));
  delete from public.user_permissions where factory_id=f and user_id=actor and module='purchasing' and action='edit';
  foreach state in array array['UNDER_REVIEW','ORDERED','READY_FOR_RECEIPT','REJECTED','NEEDS_CLARIFICATION','CANCELLED','supplier'] loop
   perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L,%L)',f,r,state,'Requester forged management'),'permission_denied',context||' cannot manage '||state);
  end loop;
  perform pg_temp.qcheck(public.supply_page(f,'mine',1,'{}',r)->'selected'->>'status'='REQUESTED',context||' can view own current status');
  insert into public.user_permissions values(f,actor,'purchasing','edit') on conflict do nothing;
 end loop;
 foreach state in array array['REQUESTED','UNDER_REVIEW','NEEDS_CLARIFICATION'] loop
  r:=pg_temp.qcall(f,'purchase_inventory',jsonb_build_object('item','other','quantity',1,'unit','piece','details','Cancellation QA'));
  if state<>'REQUESTED' then perform pg_temp.qchange(f,r,state,'Need exact specification');end if;
  delete from public.user_permissions where factory_id=f and user_id=actor and module='purchasing' and action='edit';
  perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L)',f,r,'cancel_own'),'supply_reason','existing cancellation reason required');
  perform pg_temp.qchange(f,r,'cancel_own','No longer required');
  perform pg_temp.qcheck((select status='CANCELLED' from public.purchase_requisitions where id=r),'own '||state||' cancellation permitted');
  perform pg_temp.qcheck((select count(*)>=2 from public.purchase_request_events where request_id=r),'cancellation history retained');
  insert into public.user_permissions values(f,actor,'purchasing','edit') on conflict do nothing;
 end loop;

 r:=pg_temp.qcall(f,'purchase_inventory',jsonb_build_object('item','other','quantity',1,'unit','piece','details','Foreign cancellation fixture'));
 perform set_config('request.jwt.claim.sub',other::text,true);
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L,%L)',f,r,'cancel_own','Foreign cancellation'),'supply_state','other person cannot cancel a Requested request');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform pg_temp.qcall(f,'purchase_change',jsonb_build_object('id',direct,'revision',(select revision from public.purchase_requisitions where id=direct),'action','supplier','supplier_id',supplier));
 perform pg_temp.qcheck(public.supply_page(f,'stock_purchases',1,'{}',direct)->'selected'->>'supplier_name'='Requester QA supplier','requester detail includes selected supplier');
 perform pg_temp.qchange(f,direct,'UNDER_REVIEW');perform pg_temp.qchange(f,direct,'ORDERED');
 perform pg_temp.qcheck((select status='ORDERED' from public.purchase_requisitions where id=direct),'Purchasing-authorized caller progresses with explicit supplier');
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L,%L)',f,direct,'cancel_own','Late cancellation'),'supply_state','original requester cannot cancel Ordered');
 perform pg_temp.qchange(f,direct,'READY_FOR_RECEIPT');
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L,%L)',f,direct,'cancel_own','Late cancellation'),'supply_state','original requester cannot cancel Ready');
 perform set_config('request.jwt.claim.sub',other::text,true);
 insert into public.user_permissions values(f,other,'warehouse','view') on conflict do nothing;
 perform pg_temp.qcheck(public.supply_page(f,'mine',1,'{}',direct)->'selected'='null'::jsonb,'other person cannot read original own request');
 perform pg_temp.qcheck(public.supply_page(f,'stock_purchases',1,'{}',direct)->'selected'='null'::jsonb,'Warehouse direct Other requests stay original-person scoped');
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L)',f,direct,'receive_direct'),'supply_state','other person cannot confirm direct receipt');

 perform set_config('request.jwt.claim.sub',actor::text,true);
 p:=jsonb_build_object('id',direct,'revision',(select revision from public.purchase_requisitions where id=direct),'action','receive_direct');token:=gen_random_uuid();
 delete from public.user_permissions where factory_id=f and user_id=actor and module='purchasing' and action='edit';
 perform public.supply_command(f,'purchase_change',p,token);perform public.supply_command(f,'purchase_change',p,token);
 perform pg_temp.qcheck((select status='RECEIVED' and received_by=actor and receipt_movement_id is null from public.purchase_requisitions where id=direct),'direct original requester confirms receipt without Purchasing edit or Warehouse movement');
 perform pg_temp.qcheck((select (select count(*) from public.inventory_transactions)+(select count(*) from public.finished_goods_movements))=movements,'direct receipt and retry create no inventory movement');
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L,%L)',f,direct,'cancel_own','Late cancellation'),'supply_state','Received cannot be cancelled');
 insert into public.user_permissions values(f,actor,'purchasing','edit') on conflict do nothing;
 stock:=pg_temp.qcall(f,'purchase_inventory',jsonb_build_object('item',raw,'quantity',7,'unit','kg','details',''));
 perform pg_temp.qcheck((select material_id=raw and product_id is null and details='' and unit='kg' from public.purchase_requisitions where id=stock),'known identity unit and optional Details preserved');
 perform pg_temp.qcall(f,'purchase_change',jsonb_build_object('id',stock,'revision',(select revision from public.purchase_requisitions where id=stock),'action','supplier','supplier_id',supplier));
 perform pg_temp.qchange(f,stock,'UNDER_REVIEW');perform pg_temp.qchange(f,stock,'ORDERED');perform pg_temp.qchange(f,stock,'READY_FOR_RECEIPT');
 perform pg_temp.qerror(format('select pg_temp.qchange(%L,%L,%L)',f,stock,'receive_direct'),'supply_state','stock-linked request cannot use requester Received');
 p:=jsonb_build_object('id',stock,'revision',(select revision from public.purchase_requisitions where id=stock));token:=gen_random_uuid();
 delete from public.user_permissions where factory_id=f and user_id=actor and module='warehouse' and action='edit';
 perform pg_temp.qerror(format('select public.supply_command(%L,%L,%L::jsonb,%L)',f,'receive_purchase',p,token),'permission_denied','stock receipt requires Warehouse edit');
 insert into public.user_permissions values(f,actor,'warehouse','edit') on conflict do nothing;
 perform public.supply_command(f,'receive_purchase',p,token);perform public.supply_command(f,'receive_purchase',p,token);
 perform pg_temp.qcheck((select status='RECEIVED' and receipt_movement_id is not null and received_by=actor from public.purchase_requisitions where id=stock),'stock request Received is linked to the actual external movement');
 perform pg_temp.qcheck((select sum(quantity)=7 and count(*)=1 from public.inventory_transactions where material_id=raw),'External Receipt and retry increase inventory exactly once');
 perform pg_temp.qerror(format('select pg_temp.qcall(%L,%L,%L::jsonb)',f,'receive_purchase',p),'supply_conflict','fresh repeated receipt rejected');
 perform pg_temp.qcheck(not has_table_privilege('authenticated','public.purchase_requisitions','update'),'direct status-table writes denied');
 perform pg_temp.qcheck(not has_function_privilege('authenticated','private.apply_supply_command(uuid,text,jsonb,uuid)','execute'),'private command cannot bypass public wrapper');
 set constraints all immediate;
end$test$;
select format('Purchase requester permissions, Other, search and receipt: %s assertions passed; fixtures rolled back',count(*)) result from requester_checks;
rollback;
