begin;
do $$declare x jsonb;y jsonb;f uuid;h uuid;g uuid;r jsonb;p jsonb;ops jsonb;canonical jsonb;k uuid:=gen_random_uuid();v numeric;step uuid;lot uuid;m uuid;begin
 x:=output_test.fixture('output-main');f:=(x->>'factory')::uuid;h:=(x->>'output')::uuid;g:=(x->>'g1')::uuid;
 perform output_test.ok((public.manufactured_output_capability(f)->>'available')::boolean=false,'capability remains inactive');
 perform output_test.ok(not exists(select 1 from public.finished_goods_balances where factory_id=f and on_hand<>0),'declaration never credits or reserves inventory');
 p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','95','released','95','missing_operations','[]'::jsonb)),'rejected','5','reason','Inspected output');
 perform output_test.fails(format('select output_test.receive(%L,%L,1,1,%L)',x,g,gen_random_uuid()),'output_quality_required');
 r:=private.manufactured_output_command(f,'QUALITY',h,p,1,k);
 perform output_test.ok(r=private.manufactured_output_command(f,'QUALITY',h,p,1,k),'Quality identical UUID returns original result');
 perform output_test.ok(not (r->>'requires_production_approval')::boolean,'Quality authority does not wait for Production approval');
 perform output_test.fails(format('select output_test.command(%L,''QUALITY'',%L,%L,1,%L)',f,h,p||'{"rejected":"6"}',k),'request_conflict');
 perform output_test.fails(format('select output_test.command(%L,''QUALITY'',%L,%L,1,%L)',f,h,p,gen_random_uuid()),'output_revision');
 perform output_test.fails(format('select output_test.command(%L,''QUALITY'',%L,%L,2,%L)',f,h,p||'{"rejected":"6"}',gen_random_uuid()),'output_conservation');
 perform output_test.ok(not exists(select 1 from public.finished_goods_movements where factory_id=f),'release/rejection creates no inventory or Scrap movement');
 k:=gen_random_uuid();r:=output_test.receive(x,g,92,2,k);
 perform output_test.ok(r->>'remaining_released'='3','100 recorded /5 rejected /95 released /92 received leaves 3');
 perform output_test.ok(r=output_test.receive(x,g,92,2,k),'receipt UUID retries return original result without second credit');
 perform output_test.fails(format('select output_test.receive(%L,%L,4,3,%L)',x,g,gen_random_uuid()),'output_receipt_quantity');
 perform output_test.fails(format('select output_test.receive(%L,%L,0,3,%L)',x,g,gen_random_uuid()),'output_receipt_quantity');
 select on_hand into v from public.finished_goods_balances where factory_id=f;
 perform output_test.ok(v=92,'failed over-receipt rolls ledger and source changes back');
 perform output_test.ok((select count(*)=1 from public.finished_goods_movements where factory_id=f and stock_delta<>0),'one receipt movement only');
 perform output_test.ok((select quantity_credited=92 and quantity_available=0 and physical_label is null from public.finished_goods_sources where factory_id=f),'genealogy retained without invented physical label');
 perform output_test.ok((select reserved=0 from public.finished_goods_balances where factory_id=f),'no premature Sales reservation');
 perform output_test.fails(format('select output_test.command(%L,''QUALITY'',%L,%L,3,%L)',f,h,p,gen_random_uuid()),'output_reconciliation_required');
 perform output_test.fails(format('update public.production_entries set effective_good=effective_good+1 where id=%L',x->>'entry'),'output_reconciliation_required');
 perform output_test.fails(format('update private.manufactured_outputs set quantity=1 where id=%L',h),'manufactured_output_immutable');
 perform output_test.fails(format('delete from private.manufactured_output_events where output_id=%L',h),'manufactured_output_immutable');
 r:=private.manufactured_output_command(f,'ACKNOWLEDGE',h,'{"quality_revision":2}',3,gen_random_uuid());
 perform output_test.ok((r->>'acknowledged')::boolean,'informational Production acknowledgment');
 perform output_test.ok((select on_hand=92 from public.finished_goods_balances where factory_id=f),'acknowledgment has no stock effect');

 -- Reclassification, multiple distinct groups, canonical unordered combinations.
 x:=output_test.fixture('output-groups',90,10);f:=(x->>'factory')::uuid;h:=(x->>'output')::uuid;
 select operation_snapshot into ops from private.manufactured_outputs where id=h;
 perform output_test.ok(jsonb_array_length(x->'groups')=3,'90 finished +6 single-operation +4 two-operation groups remain distinct');
 p:=jsonb_build_array(jsonb_build_object('id',x->>'g3','quantity','4','missing_operations',jsonb_build_array(x->>'step1',x->>'step2')));
 canonical:=private.manufactured_output_groups(p,ops,'meter',false);
 p:=jsonb_build_array(jsonb_build_object('id',x->>'g3','quantity','4','missing_operations',jsonb_build_array(x->>'step2',x->>'step1')));
 perform output_test.ok(canonical=private.manufactured_output_groups(p,ops,'meter',false),'operation order is irrelevant');
 p:=jsonb_build_array(jsonb_build_object('id',x->>'g3','quantity','4','missing_operations',jsonb_build_array(x->>'step1',x->>'step1')));
 perform output_test.fails(format('select private.manufactured_output_groups(%L,%L,''meter'',false)',p,ops),'output_operations');
 p:=jsonb_build_array(jsonb_build_object('id',x->>'g3','quantity','4','missing_operations',jsonb_build_array(gen_random_uuid())));
 perform output_test.fails(format('select private.manufactured_output_groups(%L,%L,''meter'',false)',p,ops),'output_operations');
 p:=jsonb_build_array(jsonb_build_object('id',x->>'g3','quantity','0.5','missing_operations','[]'::jsonb));
 perform output_test.fails(format('select private.manufactured_output_groups(%L,%L,''piece'',false)',p,ops),'output_quantity');
 p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',x->>'g1','quantity','80','released','70','missing_operations','[]'::jsonb),
 jsonb_build_object('id',x->>'g2','quantity','16','released','6','missing_operations',jsonb_build_array(x->>'step1')),
 jsonb_build_object('id',x->>'g3','quantity','4','released','0','missing_operations',jsonb_build_array(x->>'step2',x->>'step1'))),'rejected','0','reason','Printing incomplete');
 r:=private.manufactured_output_command(f,'QUALITY',h,p,1,gen_random_uuid());
 perform output_test.ok((select effective_good=90 and effective_unfinished=10 from public.production_entries where id=(x->>'entry')::uuid),'Quality reclassification preserves original declaration');
 perform output_test.ok((select sum((value->>'quantity')::numeric)=100 from jsonb_array_elements(r->'groups')),'Quality classification conserves all output');
 perform output_test.ok(not exists(select 1 from public.finished_goods_movements where factory_id=f),'reclassification is not Scrap or Warehouse stock');
 -- Legitimate new revision before any receipt/allocation; original remains immutable.
 r:=private.manufactured_output_command(f,'QUALITY',h,p,2,gen_random_uuid());
 perform output_test.ok((select count(*)=2 from private.manufactured_output_events where output_id=h and operation='QUALITY'),'Quality amendment is append-only');
 -- Existing stored-WIP movement is bound, not a second WIP ledger.
 select id into lot from public.unfinished_lots where source_entry_id=(x->>'entry')::uuid;
 update public.unfinished_lots set warehouse_quantity=6 where id=lot;
 insert into public.unfinished_movements(factory_id,lot_id,entry_id,kind,quantity,location_delta,created_by)
 values(f,lot,(x->>'entry')::uuid,'warehouse_receipt',0,6,auth.uid()) returning id into m;
 r:=private.manufactured_output_command(f,'RECEIPT',h,jsonb_build_object('group_id',x->>'g2','quantity','6','movement_id',m,'physical_confirmation',true,'location','WIP bay A'),3,gen_random_uuid());
 perform output_test.ok(r->>'lot_id'=lot::text,'stored unfinished receipt linked to existing lot and location movement');
 perform output_test.ok((select quantity_available=10 and warehouse_quantity=6 from public.unfinished_lots where id=lot),'location receipt does not increase physical WIP');
 perform output_test.fails(format('select output_test.command(%L,''DISPOSITION'',%L,%L,4,%L)',f,h,jsonb_build_object('group_id',x->>'g2','quantity','1','choice',null,'reason','Missing decision'),gen_random_uuid()),'output_disposition');
 r:=private.manufactured_output_command(f,'DISPOSITION',h,jsonb_build_object('group_id',x->>'g2','quantity','10','choice','REPLACE','reason','Choose replacement'),4,gen_random_uuid());
 perform output_test.ok(r->>'demand_item_id' is null and r->>'origin_item_id'=x->>'item','replacement releases only selected quantity ownership, retains genealogy');
 r:=private.manufactured_output_command(f,'DISPOSITION',h,jsonb_build_object('group_id',x->>'g2','quantity','6','choice','COMPLETE','reason','Finish remaining'),5,gen_random_uuid());
 perform output_test.ok(r->>'demand_item_id'=x->>'item','completion retains demand ownership');
 perform output_test.fails(format('select output_test.command(%L,''DISPOSITION'',%L,%L,6,%L)',f,h,jsonb_build_object('group_id',x->>'g2','quantity','1','choice','COMPLETE','reason','Too much allocation'),gen_random_uuid()),'output_disposition_quantity');
 perform output_test.ok((select count(*)=1 from public.production_orders where factory_id=f),'decisions do not create or schedule jobs');
 perform output_test.ok((select count(*)=1 from private.manufactured_outputs where factory_id=f),'no catalogue SKU or theoretical combination generation');

 -- Exempt receiving contracts still operate with no production Quality release.
 x:=mp_test.fixture('output-external');f:=(x->>'factory')::uuid;
 perform public.receive_warehouse_stock(f,(x->>'product')::uuid,'finished','meter',12,'opening_balance','local opening','',gen_random_uuid());
 perform public.receive_warehouse_stock(f,(x->>'product')::uuid,'finished','meter',5,'external_receipt','local purchase','',gen_random_uuid());
 perform output_test.ok((select on_hand=17 from public.finished_goods_balances where factory_id=f),'opening and external finished receipts unchanged');
 insert into public.materials(factory_id,name,code,unit) values(f,'Purchased resin','RAW-TEST','kg') returning id into m;
 perform public.receive_warehouse_stock(f,m,'material','kg',4,'external_receipt','resin','',gen_random_uuid());
 perform output_test.ok((select sum(quantity)=4 from public.inventory_transactions where factory_id=f and material_id=m),'purchased raw material receipt unchanged');
 perform output_test.ok(not exists(select 1 from private.manufactured_outputs where factory_id=f),'non-production receipts never enter new gate');
end$$;
commit;

-- Legacy recorded Good continues to post normally and cannot be re-adopted.
begin;
do $$declare x jsonb;f uuid;tech uuid;e uuid;r jsonb;begin
 x:=mp_test.fixture('output-legacy');f:=(x->>'factory')::uuid;
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 select id into tech from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 r:=public.record_lean_production(f,jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',tech,'good',7,'discarded_quantity',0,'scrap_kg',0),gen_random_uuid());e:=(r->>'id')::uuid;
 perform output_test.ok((select on_hand=7 from public.finished_goods_balances where factory_id=f),'legacy Good retains immediate credit');
 perform output_test.fails(format('select output_test.command(%L,''DECLARE'',%L,%L,0,%L)',f,e,jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','7','missing_operations','[]'::jsonb))),gen_random_uuid()),'output_legacy_or_used');
 perform output_test.ok((select count(*)=1 from public.finished_goods_movements where factory_id=f and stock_delta<>0),'legacy output never credited twice');
end$$;
commit;
select 'PASS foundation assertions',count(*) from output_test.checks;

begin;
do $$declare x jsonb;f uuid;h uuid;g uuid;p jsonb;r jsonb;ops jsonb;q numeric:=99.0000000000000000009;bad jsonb;begin
 x:=output_test.fixture('output-decimal',q);f:=(x->>'factory')::uuid;h:=(x->>'output')::uuid;g:=(x->>'g1')::uuid;
 p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity',q::text,'released',q::text,'missing_operations','[]'::jsonb)),'rejected','0','reason','Exact measured quantity');
 r:=private.manufactured_output_command(f,'QUALITY',h,p,1,gen_random_uuid());
 r:=output_test.receive(x,g,q,2,gen_random_uuid());
 perform output_test.ok((r->>'quantity')::numeric=q and (select on_hand=q from public.finished_goods_balances where factory_id=f),'19-decimal exact quantity conserved through release, receipt, ledger');
 perform output_test.fails(format('select output_test.receive(%L,%L,0.0000000000000000001,3,%L)',x,g,gen_random_uuid()),'output_receipt_quantity');
 select operation_snapshot into ops from private.manufactured_outputs where id=h;
 bad:=jsonb_build_array(jsonb_build_object('id',g,'quantity','NaN','missing_operations','[]'::jsonb));
 perform output_test.fails(format('select private.manufactured_output_groups(%L,%L,''meter'',false)',bad,ops),'output_quantity');
 bad:=jsonb_build_array(jsonb_build_object('id',g,'quantity','1','missing_operations','[]'::jsonb),jsonb_build_object('id',g,'quantity','1','missing_operations','[]'::jsonb));
 perform output_test.fails(format('select private.manufactured_output_groups(%L,%L,''meter'',false)',bad,ops),'output_quantity');
 -- A receipt may not reuse a historical/external movement even with correct quantity.
 x:=output_test.fixture('output-wrong-movement');f:=(x->>'factory')::uuid;h:=(x->>'output')::uuid;g:=(x->>'g1')::uuid;
 p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','100','released','10','missing_operations','[]'::jsonb)),'rejected','0','reason','Partial inspection');
 perform private.manufactured_output_command(f,'QUALITY',h,p,1,gen_random_uuid());
 r:=jsonb_build_object('group_id',g,'quantity','1','movement_id',public.receive_warehouse_stock(f,(x->>'product')::uuid,'finished','meter',1,'external_receipt','test supplier','',gen_random_uuid()),'physical_confirmation',true,'location','Receiving bay');
 perform output_test.fails(format('select output_test.command(%L,''RECEIPT'',%L,%L,2,%L)',f,h,r,gen_random_uuid()),'output_receipt_movement');
 perform output_test.fails(format('select output_test.command(%L,''RECEIPT'',%L,%L,2,%L)',f,h,r||'{"physical_confirmation":false}',gen_random_uuid()),'output_physical_confirmation');
 perform output_test.fails(format('select output_test.receive(%L,%L,11,2,%L)',x,g,gen_random_uuid()),'output_receipt_quantity');
 perform output_test.ok((select on_hand=1 from public.finished_goods_balances where factory_id=f),'only separately authorized external receipt survives failed manufactured receipt');
end$$;
commit;
select 'PASS total foundation assertions',count(*) from output_test.checks;
