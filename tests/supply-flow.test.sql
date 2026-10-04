-- TESTING only. Every fixture, grant, stock movement and audit change rolls back.
begin;
create temporary table supply_checks(label text);
create function pg_temp.scheck(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Supply assertion: %',label;end if;
 insert into supply_checks values(label);
end$$;
create function pg_temp.serror(statement text,expected text,label text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
  if sqlerrm<>expected then raise exception 'Supply %: expected %, got %',label,expected,sqlerrm;end if;
  insert into supply_checks values(label);return;
 end;raise exception 'Supply %: expected % but succeeded',label,expected;
end$$;
create function pg_temp.scall(f uuid,a text,p jsonb) returns uuid language sql as $$select public.supply_command(f,a,p,gen_random_uuid())$$;
create function pg_temp.change(f uuid,r uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.scall(f,'purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action',a,'reason',reason));
$$;
create function pg_temp.mchange(f uuid,r uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.scall(f,'material_change',jsonb_build_object('id',r,'revision',(select revision from public.material_requests where id=r),'action',a,'reason',reason));
$$;
do $test$
declare f uuid;actor uuid;other uuid;tech uuid;raw uuid;acc uuid;pack uuid;compound uuid;pipe uuid;pipe2 uuid;
 r uuid;manual uuid;supplier uuid;alt uuid;retry uuid;payload jsonb;x jsonb;before_stock numeric;req uuid;job uuid;line uuid;machine uuid;independent uuid;entry uuid;lot uuid;issue uuid;stmt text;context text;bad numeric;
begin
 select m.factory_id,m.user_id,m.id into f,actor,tech from public.memberships m join public.factories fac on fac.id=m.factory_id where fac.is_demo and m.is_owner and m.status='approved' limit 1;
 if actor is null then raise exception 'existing TESTING actor required';end if;
 select user_id into other from public.memberships where factory_id=f and user_id<>actor and status='approved' limit 1;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 insert into public.user_permissions(factory_id,user_id,module,action) select f,actor,module,action from public.permissions where module in ('purchasing','suppliers') on conflict do nothing;
 raw:=public.create_warehouse_material(f,jsonb_build_object('name','Supply QA raw','code','SUP-'||gen_random_uuid(),'unit','kg','inventory_kind','RAW_MATERIAL'),gen_random_uuid());
 acc:=public.create_warehouse_material(f,jsonb_build_object('name','Supply QA accessory','code','SUP-'||gen_random_uuid(),'unit','piece','inventory_kind','ACCESSORY'),gen_random_uuid());
 pack:=public.create_warehouse_material(f,jsonb_build_object('name','Supply QA packaging','code','SUP-'||gen_random_uuid(),'unit','piece','inventory_kind','PACKAGING'),gen_random_uuid());
 perform pg_temp.scheck((select inventory_kind='ACCESSORY' from public.materials where id=acc),'W09 accessory identity');
 perform pg_temp.scheck((select inventory_kind='PACKAGING' from public.materials where id=pack),'packaging identity');
 perform pg_temp.serror(format('select public.create_warehouse_material(%L,%L::jsonb,%L)',f,jsonb_build_object('name','Invalid duplicate','code','SUP-'||gen_random_uuid(),'unit','piece','inventory_kind','FINISHED_GOOD'),gen_random_uuid()),'fulfillment_invalid','P02 Warehouse cannot define finished identity');
 perform pg_temp.serror(format('select public.create_warehouse_material(%L,%L::jsonb,%L)',f,jsonb_build_object('name','Invalid WIP','code','SUP-'||gen_random_uuid(),'unit','piece','inventory_kind','SEMI_FINISHED'),gen_random_uuid()),'fulfillment_invalid','W11 new arbitrary semi prohibited');
 compound:=public.define_manufactured_product(f,null,jsonb_build_object('name','Supply QA compound','code','SUP-'||gen_random_uuid(),'unit','kg','stock_unit','kg','product_kind','MANUFACTURED_INTERMEDIATE'),jsonb_build_array(jsonb_build_object('material_id',raw,'quantity',0.8,'unit','kg')),gen_random_uuid());
 perform pg_temp.scheck((select product_kind='MANUFACTURED_INTERMEDIATE' and stock_unit='kg' from public.products where id=compound),'P03 manufactured compound');
 perform pg_temp.scheck((select batch_quantity=1 and output_unit='kg' and created_by=actor from public.bom_versions where product_id=compound),'formula explicit 1 kg basis and actor');
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'supplier_save',jsonb_build_object('name','Forged actor','requested_by',actor)),'supply_invalid','browser actor injection rejected at database boundary');
 perform pg_temp.serror(format('select public.define_manufactured_product(%L,%L,%L::jsonb,null,%L)',f,compound,jsonb_build_object('name','Invalid type change','code','SUP-'||gen_random_uuid(),'unit','piece','stock_unit','piece','product_kind','FINISHED_PRODUCT'),gen_random_uuid()),'supply_state','formula identity cannot change after typed version');
 pipe:=public.define_manufactured_product(f,null,jsonb_build_object('name','Supply QA pipe','code','SUP-'||gen_random_uuid(),'unit','piece','stock_unit','piece','formula_product_id',compound,'unit_weight_kg',1.5),null,gen_random_uuid());
 pipe2:=public.define_manufactured_product(f,null,jsonb_build_object('name','Supply QA second pipe','code','SUP-'||gen_random_uuid(),'unit','piece','stock_unit','piece','formula_product_id',compound,'unit_weight_kg',2),null,gen_random_uuid());
 perform pg_temp.scheck((select count(*)=2 from public.products where formula_product_id=compound),'P04 formula reused without identity duplication');
 x:=public.product_requirements(f,pipe,10,'piece');
 perform pg_temp.scheck((x->>'compound_quantity_kg')::numeric=15 and (x->'raw_materials'->0->>'quantity')::numeric=12 and (x->>'theoretical')::boolean,'P06 scaled pipe compound and raw calculation');
 perform pg_temp.scheck((select count(*)=0 from public.inventory_transactions where material_id=raw),'formula calculation never consumes actual stock');
 perform pg_temp.serror(format('select public.product_requirements(%L,%L,10,%L)',f,pipe,'meter'),'supply_invalid','P05 no implicit cross-unit calculation');
 perform pg_temp.serror(format('select public.define_manufactured_product(%L,null,%L::jsonb,%L::jsonb,%L)',f,jsonb_build_object('name','Bad formula','code','SUP-'||gen_random_uuid(),'unit','kg','stock_unit','kg','product_kind','MANUFACTURED_INTERMEDIATE'),jsonb_build_array(jsonb_build_object('material_id',acc,'quantity',1,'unit','kg')),gen_random_uuid()),'supply_invalid','P05 accessory is not raw formula ingredient');
 perform pg_temp.serror(format('select public.define_manufactured_product(%L,null,%L::jsonb,null,%L)',f,jsonb_build_object('name','Bad WIP','code','SUP-'||gen_random_uuid(),'unit','piece','stage','wip'),gen_random_uuid()),'supply_invalid','P01 manufactured identity uses intended Product path');
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=pipe::text;
 perform pg_temp.scheck((x->>'on_hand')::numeric=0 and (select count(*)=1 from private.warehouse_inventory_rows(f) value where value->>'id'=pipe::text),'W07 W10 one zero-stock Product row');
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=raw::text;
 perform pg_temp.scheck(x->>'item_type'='RAW_MATERIAL' and (x->>'on_hand')::numeric=0,'W08 raw stock identity');
 -- Ambiguous historical quantities cannot be presented as a configured zero.
 update public.products set stock_unit=null where id=pipe2;
 perform public.adjust_finished_stock(f,pipe2,'meter',3,'QA legacy meter');
 perform public.adjust_finished_stock(f,pipe2,'piece',4,'QA legacy piece');
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=pipe2::text;
 perform pg_temp.scheck(x->'on_hand'='null'::jsonb and x->'reserved'='null'::jsonb and x->'projected'='null'::jsonb and jsonb_array_length(x->'unit_breakdown')=2,'ambiguous primary-unit amounts NULL with two typed breakdowns');
 perform pg_temp.scheck(not private.warehouse_filter_matches(x,'{"on_hand":{"op":"eq","value":0}}'),'unknown primary stock is not zero-stock filter');
 -- Stock-linked procurement includes reservations, ordered supplier incoming and adjusted quantities.
 perform public.receive_warehouse_stock(f,raw,'material','kg',20,'opening_balance');
 perform public.configure_warehouse_material(f,raw,20,50);
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=raw::text;
 perform pg_temp.scheck((x->>'suggested_quantity')::numeric=30 and (x->>'can_purchase')::boolean,'R47 Max minus Projected and equality threshold');
 payload:=jsonb_build_object('item',raw,'unit','kg','projected',20,'quantity',25);retry:=gen_random_uuid();
 r:=public.supply_command(f,'purchase_stock',payload,retry);
 perform pg_temp.scheck(r=public.supply_command(f,'purchase_stock',payload,retry),'R38 same id retry no duplicate');
 perform pg_temp.scheck(r=pg_temp.scall(f,'purchase_stock',payload),'R38 different id duplicate active returns existing');
 perform pg_temp.scheck((select quantity=25 and material_id=raw and stock_context->>'projected'='20' and requested_by=actor and source_context='Warehouse' from public.purchase_requisitions where id=r),'R46 R48 stock linked adjusted quantity and captured stock context');
 perform pg_temp.scheck(not exists(select 1 from public.production_orders where product_id=raw),'R35 purchased material never creates Production');
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=raw::text;
 perform pg_temp.scheck((x->>'incoming')::numeric=0 and x->>'replenishment_status'='PURCHASE_REQUESTED' and not (x->>'can_purchase')::boolean,'requested PR suppresses duplicate without inventing Incoming');
 supplier:=pg_temp.scall(f,'supplier_save','{"name":"Supply QA supplier","primary_contact":"Mina","phone":"+966555123456","email":"supply@example.test","notes":"QA contact","category":"Supply QA resin","relationship":"PRIMARY"}');
 alt:=pg_temp.scall(f,'supplier_save','{"name":"Supply QA alternative","category":"Supply QA resin","relationship":"ALTERNATIVE"}');
 perform pg_temp.scheck((select phone='+966555123456' and email='supply@example.test' and primary_contact='Mina' and notes='QA contact' from public.suppliers where id=supplier),'S64 S65 supplier contacts');
 perform pg_temp.scheck((select count(*)=1 from public.supplier_category_links where factory_id=f and supplier_id=supplier and relationship='PRIMARY'),'S66 primary category relationship');
 perform pg_temp.scheck((select count(*)=1 from public.supplier_category_links where factory_id=f and supplier_id=alt and relationship='ALTERNATIVE'),'S67 S68 alternative association');
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'supplier_save',jsonb_build_object('id',alt,'name','Supply QA alternative','category','Supply QA resin','relationship','PRIMARY')),'supply_conflict','primary replacement requires explicit choice');
 perform pg_temp.scall(f,'supplier_save',jsonb_build_object('id',alt,'name','Supply QA alternative','category','Supply QA resin','relationship','PRIMARY','replace_primary',true));
 perform pg_temp.scheck((select count(*)=1 from public.supplier_category_links where factory_id=f and relationship='PRIMARY' and category_id=(select category_id from public.supplier_category_links where factory_id=f and supplier_id=alt)) and (select relationship='ALTERNATIVE' from public.supplier_category_links where factory_id=f and supplier_id=supplier),'S66 S67 explicit Primary replacement retains previous Alternative');
 perform pg_temp.scall(f,'purchase_change',jsonb_build_object('id',r,'revision',1,'action','supplier','supplier_id',supplier));
 perform pg_temp.scheck((select supplier_id=supplier from public.purchase_requisitions where id=r),'S69 explicit selected supplier');
 perform pg_temp.change(f,r,'UNDER_REVIEW');perform pg_temp.change(f,r,'ORDERED');
 perform pg_temp.scheck((select status='ORDERED' from public.purchase_requisitions where id=r),'R57 R58 Requested Review Ordered');
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=raw::text;
 perform pg_temp.scheck((x->>'incoming')::numeric=25 and (x->>'projected')::numeric=45,'ordered supplier quantity enters Incoming once');
 perform pg_temp.change(f,r,'READY_FOR_RECEIPT');
 perform pg_temp.scheck((select status='READY_FOR_RECEIPT' from public.purchase_requisitions where id=r),'R59 ready transition');
 payload:=jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r));retry:=gen_random_uuid();
 perform public.supply_command(f,'receive_purchase',payload,retry);perform public.supply_command(f,'receive_purchase',payload,retry);
 perform pg_temp.scheck((select sum(quantity)=45 from public.inventory_transactions where material_id=raw),'R71 stock credited exactly once');
 perform pg_temp.scheck((select status='RECEIVED' and received_by=actor and received_at is not null and receipt_movement_id is not null from public.purchase_requisitions where id=r),'R60 R72 received actor and movement');
 perform pg_temp.scheck((select kind='external_receipt' and quantity=25 and unit='kg' and created_by=actor from public.inventory_transactions where id=(select receipt_movement_id from public.purchase_requisitions where id=r)),'R70 existing External Receipt ledger');
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'receive_purchase',payload),'supply_conflict','second receipt with fresh id cannot recredit');
 perform pg_temp.scheck((select count(*)=6 from public.purchase_request_events where request_id=r),'append-only full purchase lifecycle history');
 -- Free-text requests: all authorized contexts; details required, notes optional.
 select sum(quantity) into before_stock from public.inventory_transactions where factory_id=f;
 foreach context in array array['Production','Maintenance','Administration','Other authorized department'] loop
  manual:=pg_temp.scall(f,'purchase_manual',jsonb_build_object('item_name','Special repair component','quantity',2,'unit','piece','details','Required dimensions and intended use','source_context',context));
  perform pg_temp.scheck((select requested_by=actor and requested_by_name<>'' and source_context=context and notes='' and material_id is null and product_id is null from public.purchase_requisitions where id=manual),'R49-55 free text actor/context/details/optional notes: '||context);
  perform pg_temp.change(f,manual,'UNDER_REVIEW');
  perform pg_temp.scall(f,'purchase_change',jsonb_build_object('id',manual,'revision',2,'action','supplier','supplier_id',supplier));
  perform pg_temp.change(f,manual,'ORDERED');perform pg_temp.change(f,manual,'READY_FOR_RECEIPT');
  if other is not null then
   perform set_config('request.jwt.claim.sub',other::text,true);
   perform pg_temp.serror(format('select pg_temp.change(%L,%L,%L)',f,manual,'receive_direct'),'supply_state','R75 only original requester receives: '||context);
   perform set_config('request.jwt.claim.sub',actor::text,true);
  end if;
  perform pg_temp.change(f,manual,'receive_direct');
  perform pg_temp.scheck((select status='RECEIVED' and received_by=actor and receipt_movement_id is null from public.purchase_requisitions where id=manual),'R73-75 direct receipt has no movement: '||context);
 end loop;
 perform pg_temp.scheck(before_stock=(select sum(quantity) from public.inventory_transactions where factory_id=f),'R73 R74 all direct purchases leave stock unchanged');
 foreach bad in array array[0,-1,'NaN'::numeric,'Infinity'::numeric] loop
  perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'purchase_manual',jsonb_build_object('item_name','Invalid quantity','quantity',bad,'unit','piece','details','Description','source_context','Maintenance')),'supply_invalid','positive finite purchase quantity '||bad::text);
 end loop;
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'purchase_manual','{"item_name":"Missing details","quantity":1,"unit":"piece","source_context":"Maintenance"}'),'supply_invalid','R52 details mandatory');
 manual:=pg_temp.scall(f,'purchase_manual','{"item_name":"Clarify fitting","quantity":1,"unit":"piece","details":"Original size","notes":"Optional original note","source_context":"Maintenance"}');
 perform pg_temp.serror(format('select pg_temp.change(%L,%L,%L)',f,manual,'NEEDS_CLARIFICATION'),'supply_reason','R61 clarification needs reason');
 perform pg_temp.serror(format('select pg_temp.change(%L,%L,%L)',f,manual,'REJECTED'),'supply_reason','R62 rejection needs reason');
 perform pg_temp.change(f,manual,'NEEDS_CLARIFICATION','Please supply exact diameter');
 perform pg_temp.change(f,manual,'clarify','Diameter is 25 mm');
 perform pg_temp.scheck((select status='REQUESTED' and details='Original size' and notes='Optional original note' from public.purchase_requisitions where id=manual),'requester clarification preserves original specification');
 perform pg_temp.scheck((select count(*)=3 from public.purchase_request_events where request_id=manual),'clarification question and reply history');
 perform pg_temp.change(f,manual,'CANCELLED','No longer required');
 perform pg_temp.scheck((select status='CANCELLED' and purchasing_note='No longer required' from public.purchase_requisitions where id=manual),'R63 cancellation reason/history');
 -- Explicit production material requests and full issues on the authoritative typed ledgers.
 perform public.receive_warehouse_stock(f,acc,'material','piece',5,'opening_balance');
 perform public.receive_warehouse_stock(f,pack,'material','piece',10,'opening_balance');
 perform public.adjust_finished_stock(f,compound,'kg',8,'QA opening compound');
 foreach payload in array array[jsonb_build_object('item',raw,'unit','kg','quantity',5),jsonb_build_object('item',acc,'unit','piece','quantity',2),jsonb_build_object('item',pack,'unit','piece','quantity',2),jsonb_build_object('item',compound,'unit','kg','quantity',2)] loop
  issue:=pg_temp.scall(f,'material_request',payload);
  perform pg_temp.scheck((select status='REQUESTED' and production_item_id is null and requested_by=actor from public.material_requests where id=issue),'M39-41 request existing item no required machine/line');
  perform pg_temp.mchange(f,issue,'issue');
  perform pg_temp.scheck((select status='ISSUED' and movement_id is not null and issued_by=actor and issued_at is not null from public.material_requests where id=issue),'M43 M44 issue actor/time/movement trace');
  perform pg_temp.mchange(f,issue,'receive');
  perform pg_temp.scheck((select status='RECEIVED' and received_by=actor and received_at is not null from public.material_requests where id=issue),'Production acknowledges material delivery');
 end loop;
 perform pg_temp.scheck((select on_hand=6 from public.finished_goods_balances where product_id=compound and unit='kg'),'M43 compound issue decreases kg stock');
 perform pg_temp.scheck((select sum(quantity)=40 from public.inventory_transactions where material_id=raw),'M43 raw issue decreases authoritative stock');
 issue:=pg_temp.scall(f,'material_request',jsonb_build_object('item',raw,'unit','kg','quantity',100));
 perform pg_temp.serror(format('select pg_temp.mchange(%L,%L,%L)',f,issue,'issue'),'supply_insufficient','M45 insufficient quantity is rejected atomically');
 perform pg_temp.scheck((select status='REQUESTED' and movement_id is null from public.material_requests where id=issue),'failed issue leaves request and inventory unchanged');
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'material_request',jsonb_build_object('item',raw,'unit','piece','quantity',1)),'supply_invalid','material unit spoofing denied');
 -- Production Good + durable WIP, active quantity and planned future Incoming remain distinct.
 update public.production_shifts set archived=true where factory_id=f and not archived;
 insert into public.production_lines(factory_id,name,code) values(f,'Supply QA execution line','SUP-'||gen_random_uuid()) returning id into line;
 insert into public.work_centers(factory_id,name,code,line_id,category_id) select f,'Supply QA execution machine','SUP-'||gen_random_uuid(),line,category_id from public.work_centers where factory_id=f and category_id is not null limit 1 returning id into machine;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,machine,pipe,100,'piece');
 insert into public.work_centers(factory_id,name,code,category_id,dependency_mode) select f,'Supply QA secondary machine','SUP-'||gen_random_uuid(),category_id,'independent' from public.work_centers where id=machine returning id into independent;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,independent,pipe,100,'piece');
 req:=public.create_production_request(f,'Supply QA job','normal',null,'QA explicit production',jsonb_build_array(jsonb_build_object('product_id',pipe,'quantity',100,'unit','piece')));
 select id into job from public.production_orders where request_id=req;
 update public.production_orders set line_id=line,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=job;
 perform public.start_product_item(f,job);
 entry:=public.record_production(f,'line',line,job,tech,60,5,unfinished=>35,remaining_work=>'Printing');
 select id into lot from public.unfinished_lots where source_entry_id=entry;
 perform pg_temp.scall(f,'receive_wip',jsonb_build_object('lot',lot,'quantity',20));
 select value into x from private.warehouse_inventory_rows(f) value where value->>'id'=pipe::text;
 perform pg_temp.scheck((x->>'on_hand')::numeric=60 and (x->>'semi_finished')::numeric=20 and (x->>'in_production')::numeric=40 and (x->>'incoming')::numeric=0,'W12 W14 W15 Finished stored Semi active remaining future Incoming separate');
 perform pg_temp.scheck((select quantity_available=35 and warehouse_quantity=20 from public.unfinished_lots where id=lot),'W17 physical receipt preserves lot total');
 perform pg_temp.scheck(private.warehouse_filter_matches(x,'{"semi_finished":{"op":"gt","value":0},"in_production":{"op":"gt","value":0},"item_type":["RAW_MATERIAL","FINISHED_GOOD"]}'),'F22 F26 F27 numeric AND and category OR');
 perform pg_temp.scheck((public.supply_page(f,'lots',1,'{}',pipe)->'rows'->0->>'remaining_work')='Printing','W13 durable remaining-work detail');
 perform pg_temp.scall(f,'acknowledge_good',jsonb_build_object('entry',entry));perform pg_temp.scall(f,'acknowledge_good',jsonb_build_object('entry',entry));
 perform pg_temp.scheck((select on_hand=60 from public.finished_goods_balances where product_id=pipe and unit='piece') and (select count(*)=1 from public.production_receipt_acknowledgments where entry_id=entry),'R84 Good physical acknowledgment never double credits');
 perform pg_temp.serror(format('select public.record_production(%L,%L,%L,%L,%L,20,0,input_lot=>%L,input_quantity=>20)',f,'machine',independent,job,tech,lot),'unfinished_insufficient','stored WIP cannot be consumed without Warehouse issue');
 issue:=pg_temp.scall(f,'material_request',jsonb_build_object('item',lot,'item_type','lot','unit','piece','quantity',10));
 perform pg_temp.mchange(f,issue,'issue');perform pg_temp.mchange(f,issue,'receive');
 perform pg_temp.scheck((select quantity_available=35 and warehouse_quantity=10 from public.unfinished_lots where id=lot),'M42 WIP issue moves location without subtracting the physical lot twice');
 perform public.record_production(f,'machine',independent,job,tech,20,0,input_lot=>lot,input_quantity=>20);
 perform pg_temp.scheck((select quantity_available=15 and warehouse_quantity=10 from public.unfinished_lots where id=lot) and (select on_hand=80 from public.finished_goods_balances where product_id=pipe),'W17 R85 WIP completion conserves and credits Good once');
 perform pg_temp.serror(format('select public.correct_production_entry(%L,%L,60,5,%L,unfinished=>25,remaining_work=>%L)',f,entry,'Invalid stored correction','Printing'),'unfinished_already_consumed','correction cannot erase stored or consumed WIP');
 -- Kg compound jobs reuse the same execution, Good, Scrap and history model.
 insert into public.production_lines(factory_id,name,code) values(f,'Supply QA kg line','SUP-'||gen_random_uuid()) returning id into line;
 insert into public.work_centers(factory_id,name,code,line_id,category_id) select f,'Supply QA kg machine','SUP-'||gen_random_uuid(),line,category_id from public.work_centers where factory_id=f and category_id is not null limit 1 returning id into machine;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,machine,compound,10,'kg');
 req:=public.create_production_request(f,'Supply QA compound job','normal',null,'Explicit kg production',jsonb_build_array(jsonb_build_object('product_id',compound,'quantity',10,'unit','kg')));
 select id into job from public.production_orders where request_id=req;
 update public.production_orders set line_id=line,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=job;
 perform public.start_product_item(f,job);
 entry:=public.record_production(f,'line',line,job,tech,4,1);
 perform pg_temp.scheck((select unit='kg' and effective_good=4 and effective_scrap=1 from public.production_entries where id=entry),'kg production retains separate Good and Scrap');
 perform pg_temp.scheck((select on_hand=10 from public.finished_goods_balances where product_id=compound and unit='kg'),'kg Production credits Good only once');
 perform pg_temp.scheck(public.production_history(f,'{"measurement_unit":"kg"}')->>'total' is not null,'kg history unit recognized');
 -- Per-person denial remains in force even for owners; own page never leaks a broader selected request.
 delete from public.user_permissions where factory_id=f and user_id=actor and module in ('purchasing','suppliers');
 perform pg_temp.serror(format('select public.supply_page(%L,%L)',f,'purchases'),'permission_denied','P76 owner without Purchasing view cannot browse all');
 perform pg_temp.serror(format('select pg_temp.change(%L,%L,%L,%L)',f,manual,'CANCELLED','Forged permission'),'permission_denied','P76 no Purchasing management from job title');
 perform pg_temp.serror(format('select pg_temp.scall(%L,%L,%L::jsonb)',f,'supplier_save','{"name":"Forged supplier"}'),'permission_denied','P78 supplier management requires person grant');
 perform pg_temp.scheck(public.supply_page(f,'mine') is not null,'R56 own purchase visibility without broad grant');
 if other is not null then
  perform set_config('request.jwt.claim.sub',other::text,true);
  perform pg_temp.scheck(public.supply_page(f,'mine',1,'{}',manual)->'selected'='null'::jsonb,'own selected detail does not leak another requester');
 end if;
 perform pg_temp.scheck(not has_table_privilege('authenticated','public.purchase_requisitions','update') and not has_table_privilege('authenticated','public.material_requests','insert'),'P79 database mutation boundary cannot bypass transitions');
 perform pg_temp.scheck(not has_function_privilege('anon','public.supply_command(uuid,text,jsonb,uuid)','execute'),'anonymous supply commands denied');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform pg_temp.serror(format('select public.supply_page(%L,%L,1,%L::jsonb)',f,'mine','{"unknown":1}'),'supply_invalid','unknown reader filters rejected');
 perform pg_temp.serror(format('select public.supply_page(%L,%L,1,%L::jsonb)',f,'mine','{"status":"REQUESTED"}'),'supply_invalid','invalid categorical filter shape rejected');
 set constraints all immediate;
end$test$;
select format('Products, recipes, Warehouse quantities, material flow, Purchasing, suppliers, receipt idempotency and per-person permissions: %s assertions passed; all fixtures rolled back',count(*)) result from supply_checks;
rollback;
