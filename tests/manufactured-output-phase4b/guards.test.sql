begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;w jsonb;v jsonb;f uuid;i uuid;r jsonb;p jsonb;so uuid;sl uuid;original uuid;begin
 x:=output4_test.context('Sales retained');f:=(x->>'factory')::uuid;original:=(x->>'item')::uuid;
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,100,'meter') returning id into sl;
 perform private.reserve_finished(f,sl,90);
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,sl,original,10);
 w:=output4_test.decision(x,'COMPLETE',10);i:=(w->>'item_id')::uuid;
 r:=output4b_test.revise(x,w,'CHANGE','REPLACE');
 perform late_test.ok((select reserved=90 and on_hand=90 from public.finished_goods_balances where factory_id=f),'decision change preserves reserved ninety and stock ninety');
 perform late_test.ok((select quantity=10 and received_quantity=0 and released_quantity=0 from public.sales_incoming_allocations where item_id=original),'original incoming ten neither released nor redistributed');
 perform late_test.ok(private.quality_production_remaining(f,i)=0 and private.quality_production_remaining(f,(r#>>'{successor,item_id}')::uuid)=10,'retired forecast zero successor ten');
 perform late_test.ok((select count(*)=3 from public.production_orders where factory_id=f),'only explicit successor created no automatic production');
 perform late_test.fails(format('select public.supply_command(%L,''material_change'',%L,%L)',f,jsonb_build_object('id',w->>'material_request_id','revision',2,'action','issue','reason','Forbidden old request issue'),gen_random_uuid()),'supply_state');
 perform late_test.fails(format('update public.material_requests set reason=''overwrite history'' where id=%L',w->>'material_request_id'),'output_work_retired');
 perform late_test.fails(format('delete from public.material_requests where id=%L',w->>'material_request_id'),'manufactured_output_immutable');
 perform late_test.fails(format('select private.output_recovery_validate(%L,%L)',f,jsonb_build_object('item',i)),'output_work_retired');
 -- An adversarial direct incoming commitment must block retirement rather than
 -- invoke Sales' existing cancellation redistribution trigger.
 w:=r->'successor';i:=(w->>'item_id')::uuid;
 insert into public.sales_incoming_allocations(factory_id,line_id,item_id,quantity) values(f,sl,i,1);
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_committed');
 perform late_test.ok((select quantity=1 and released_quantity=0 from public.sales_incoming_allocations where item_id=i),'direct commitment rejection preserves commitment');

 x:=output4_test.context('Elapsed real slot');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);i:=(w->>'item_id')::uuid;
 perform public.plan_product_item(f,i,(x->>'line')::uuid,now()-interval '20 seconds');
 perform late_test.ok((select start_time<=now() from public.production_orders where id=i),'normal Planning accepted elapsed slot within its existing tolerance');
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'planning_already_started');
 perform late_test.ok((select status='planned' and line_id is not null from public.production_orders where id=i),'elapsed rejection keeps schedule');
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,5,%L)',f,i,output4b_test.payload(x,w)||jsonb_build_object('reason',' '),gen_random_uuid()),'output_revision_invalid');

 -- Physical evidence is independently authoritative even if a corrupted fixture
 -- has a REQUESTED label. Production code never performs this corruption.
 x:=output4_test.context('Issue evidence');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Measured physical issue'),gen_random_uuid());
 update public.material_requests set status='REQUESTED',issued_at=null,issued_by=null,movement_id=null where id=(w->>'material_request_id')::uuid;
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_material_issued');
 perform late_test.ok((select warehouse_quantity=0 and quantity_available=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'issue command evidence prevents fabricated reversal');

 x:=output4_test.context('Separate source allocations');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',4);
 v:=output4_test.decision(x||jsonb_build_object('revision',5),'COMPLETE',6);
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Issue only first four'),gen_random_uuid());
 p:=output4b_test.payload(x,v);p:=jsonb_set(p,'{expected_state,material_revision}','"0"');
 perform late_test.fails(format('select public.revise_manufactured_completion(%L,%L,%L,6,%L)',f,v->>'item_id',p,gen_random_uuid()),'output_revision');
 r:=output4b_test.revise(x,v);
 perform late_test.ok((select assigned=4 and reserved=0 from private.output_work_allocations(f,(x->>'lot')::uuid)) and not private.output_work_retired(f,(w->>'item_id')::uuid),'cancel only untouched allocation preserves issued sibling four');
 perform late_test.ok((select quantity_available=10 and warehouse_quantity=6 from public.unfinished_lots where id=(x->>'lot')::uuid) and (select status='ISSUED' from public.material_requests where id=(w->>'material_request_id')::uuid),'no reversal of sibling issue or physical stock');

 x:=output4_test.context('All Scrap cannot undo');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);y:=output4_test.start(x,w);
 r:=public.record_manufactured_output(f,output2_test.payload(y,0)||jsonb_build_object('input_lot',x->>'lot','input_quantity',10,'discarded_quantity',10,'scrap_kg',.75),gen_random_uuid());
 perform late_test.fails(format('select output4b_test.revise(%L,%L)',x,w),'output_work_started');
 perform late_test.ok((select quantity_available=0 from public.unfinished_lots where id=(x->>'lot')::uuid) and (select effective_scrap_kg=.75 and effective_good=0 from public.production_entries where id=(r->>'entry_id')::uuid),'all-Scrap consumption and measured KG cannot be undone');
end$$;
set constraints all immediate;
select count(*) assertions from late_test.checks;
rollback;
