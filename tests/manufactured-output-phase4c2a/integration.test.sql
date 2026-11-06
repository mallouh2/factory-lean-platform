do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55491 then raise exception 'Disposable localhost only';end if;end$$;
create schema output4c_test;
create function output4c_test.amendment(x jsonb,kind text default 'additional') returns jsonb language plpgsql as $$
declare g jsonb;groups jsonb:='[]';begin
 for g in select value from jsonb_array_elements(private.output_quality((x->>'factory')::uuid,(x->>'output')::uuid)->'groups') loop
  if jsonb_array_length(g->'missing_operations')=0 and kind='additional' then g:=g||'{"quantity":"85","released":"85"}';end if;
  if jsonb_array_length(g->'missing_operations')>0 then
   if kind='reduce' then g:=g||'{"quantity":"6","released":"6"}';
   elsif kind='operations' then g:=g||jsonb_build_object('id',gen_random_uuid(),'missing_operations',jsonb_build_array(x->>'step2',x->>'step1'));
   end if;
  end if;
  groups:=groups||jsonb_build_array(g);
 end loop;
 if kind='additional' then groups:=groups||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','5','released','5','missing_operations',jsonb_build_array(x->>'step1')));end if;
 return jsonb_build_object('groups',groups,'rejected',case when kind='reduce' then '4' else '0' end,'reason','Authoritative controlled Quality finding');
end$$;
create function output4c_test.publish(x jsonb,p jsonb,rev bigint default 5,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.manufactured_output_command((x->>'factory')::uuid,'QUALITY',(x->>'output')::uuid,p,rev,k)
$$;
create function output4c_test.identify(x jsonb) returns uuid language plpgsql as $$
declare s uuid;e uuid;begin
 select entry_id into e from private.manufactured_outputs where id=(x->>'output')::uuid;
 select id into s from public.finished_goods_sources where factory_id=(x->>'factory')::uuid and entry_id=e;
 perform public.source_stock_command((x->>'factory')::uuid,'identify',jsonb_build_object('source',s,'quantity','90','label','Identifiable controlled source','physically_identified',true),'[]',gen_random_uuid());return s;
end$$;
create function output4c_test.explode() returns trigger language plpgsql as $$begin
 if new.kind='quality_rejection' then raise exception 'fixture_unexpected';end if;return new;
end$$;
begin;
truncate late_test.checks;
do $$declare x jsonb;y jsonb;f uuid;w jsonb;p jsonb;r jsonb;k uuid;e jsonb;src uuid;so uuid;sl uuid;g uuid;n bigint;before_stock jsonb;before_work jsonb;before_entry jsonb;begin
 x:=output4_test.context('Additional five');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);src:=output4c_test.identify(x);
 select to_jsonb(z) into before_work from private.manufactured_completion_work z where item_id=(w->>'item_id')::uuid;
 select to_jsonb(z) into before_stock from public.finished_goods_balances z where factory_id=f;
 select to_jsonb(z) into before_entry from public.production_entries z where id=(select entry_id from private.manufactured_outputs where id=(x->>'output')::uuid);
 p:=output4c_test.amendment(x);k:=gen_random_uuid();r:=output4c_test.publish(x,p,5,k);
 perform late_test.ok(r->>'accounting_applied'='false' and r->>'reconciliation_pending'='true' and r->>'requires_production_approval'='false','finding authoritative without Production approval');
 perform late_test.ok(r->>'applied_quality_revision'='2' and private.output_quality(f,(x->>'output')::uuid)->>'revision'='2' and private.output_finding(f,(x->>'output')::uuid)->>'revision'='6','latest finding separated from applied revision');
 perform late_test.ok((select to_jsonb(z)=before_stock from public.finished_goods_balances z where factory_id=f),'no physical balance change');
 perform late_test.ok((select to_jsonb(z)=before_entry from public.production_entries z where id=(before_entry->>'id')::uuid),'original technician evidence unchanged');
 perform late_test.ok((select to_jsonb(z)=before_work from private.manufactured_completion_work z where item_id=(w->>'item_id')::uuid),'unaffected ten allocation immutable');
 perform late_test.ok((select assigned=10 and reserved=10 from private.output_work_allocations(f,(x->>'lot')::uuid)) and not private.output_work_held(f,(w->>'item_id')::uuid),'additional five not allocated to existing ten');
 perform late_test.ok((select quantity_created=10 and warehouse_quantity=10 from public.unfinished_lots where id=(x->>'lot')::uuid) and (select count(*)=1 from private.manufactured_output_lots where factory_id=f),'no fabricated new unfinished stock');
 perform late_test.ok(private.output_source_held(f,(before_entry->>'id')::uuid) and private.output_stock_free(f,(x->>'product')::uuid,'meter')=0,'affected finished source held conservatively');
 perform late_test.ok(output4c_test.publish(x,p,5,k)=r and (select count(*)=2 from private.manufactured_output_events where factory_id=f and operation='QUALITY'),'UUID one new finding and notification');
 perform late_test.fails(format('select output4c_test.publish(%L,%L,5,%L)',x,p||'{"reason":"Changed UUID intent"}',k),'request_conflict');
 e:=public.manufactured_output_read(f,'notifications')->'rows'->0;
 perform late_test.ok(e->>'unread'='true' and e#>>'{quality,revision}'='6' and e#>>'{accounting,applied_revision}'='2' and e#>>'{accounting,pending}'='true','Production notification and explicit accounting contract');
 perform public.manufactured_output_command(f,'ACKNOWLEDGE',(x->>'output')::uuid,'{"quality_revision":6}',6,gen_random_uuid());
 perform late_test.ok(private.output_source_held(f,(before_entry->>'id')::uuid) and public.manufactured_output_read(f,'notifications')#>>'{rows,0,unread}'='false','ACK never clears hold');
 perform late_test.ok(public.finished_source_stock(f,(x->>'product')::uuid,'meter')#>>'{rows,0,selectable}'='0','source selector excludes held stock');
 perform late_test.ok((select on_hand=90 and reserved=0 and projected=10 from private.finished_inventory_projection(f) where product_id=(x->>'product')::uuid),'physical ninety retained forecast only unaffected ten');
 perform late_test.ok((select value->>'available'='0' from private.warehouse_inventory_rows(f) value where value->>'entity'='finished'),'Warehouse available excludes hold');
 perform late_test.ok(public.manufactured_receiving_read(f)#>>'{rows,0,accounting,applied_revision}'='2','receiving reads applied classification separately');
 perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Unchanged material remains eligible'),gen_random_uuid());
 perform late_test.ok((select warehouse_quantity=0 and quantity_available=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'unaffected unfinished source still issues normally');
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,10,'meter') returning id into sl;
 perform late_test.fails(format('select private.reserve_finished(%L,%L,1)',f,sl),'output_quality_hold');
 perform late_test.fails(format('select private.source_assign_reservation(%L,%L,%L)',f,sl,jsonb_build_array(jsonb_build_object('source_id',src,'quantity','1'))),'source_committed');
 perform late_test.fails(format('select public.source_stock_command(%L,''adjust'',%L,%L,%L)',f,jsonb_build_object('product',x->>'product','unit','meter','quantity','-1','reason','Held stock may not leave'),jsonb_build_array(jsonb_build_object('source_id',src,'quantity','1')),gen_random_uuid()),'output_quality_hold');
 perform late_test.ok((select to_jsonb(z)=before_stock from public.finished_goods_balances z where factory_id=f),'denied stock-out and reservation roll back');

 -- Classification change protects reserved, issued and active work, and the
 -- transitive inspected output of recovery. No physical reversal occurs.
 x:=output4_test.context('Obsolete operations');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 perform public.plan_product_item(f,(w->>'item_id')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '5 days');
 r:=output4c_test.publish(x,output4c_test.amendment(x,'operations'));
 perform late_test.ok(private.output_work_held(f,(w->>'item_id')::uuid),'classification change holds linked work');
 perform late_test.ok(public.manufactured_completion_read(f)#>>'{work,0,held}'='true' and public.manufactured_completion_read(f)#>>'{rows,0,available_to_allocate}'='0','Planning read reports hold and zero selectable source');
 perform late_test.ok(public.production_start_readiness(f,(w->>'item_id')::uuid)->>'quality_hold'='true','Start read distinguishes Quality hold from physical and queue readiness');
 perform late_test.fails(format('select public.supply_command(%L,''material_change'',%L,%L)',f,jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Obsolete request cannot issue'),gen_random_uuid()),'output_quality_hold');
 perform late_test.fails(format('select public.start_product_item(%L,%L)',f,w->>'item_id'),'output_quality_hold');
 perform late_test.fails(format('select private.output_recovery_validate(%L,%L)',f,jsonb_build_object('item',w->>'item_id')),'output_quality_hold');
 perform late_test.fails(format('select public.receive_manufactured_output(%L,%L,%L,6,%L)',f,x->>'output',jsonb_build_object('group_id',x->>'group','quantity','1','location','Recovery bay','physical_confirmation',true),gen_random_uuid()),'output_quality_hold');
 perform late_test.fails(format('select public.plan_manufactured_completion(%L,%L,%L,6,%L)',f,x->>'output',jsonb_build_object('group_id',x->>'group','quantity','1','choice','REPLACE','reason','Held disposition','operations','[]'::jsonb),gen_random_uuid()),'output_quality_hold');
 perform late_test.ok((select status='REQUESTED' and movement_id is null from public.material_requests where id=(w->>'material_request_id')::uuid) and private.quality_production_remaining(f,(w->>'item_id')::uuid)=0,'request preserved but held forecast excluded');
 -- Later Quality evidence cannot accidentally lift a prior hold.
 r:=output4c_test.publish(x,jsonb_build_object('groups',private.output_quality(f,(x->>'output')::uuid)->'groups','rejected','0','reason','Further inspection original classification'),6);
 perform late_test.ok(r->>'reconciliation_pending'='true' and private.output_work_held(f,(w->>'item_id')::uuid),'new finding cannot implicitly release unresolved hold');

 x:=output4_test.context('Already processed');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);y:=output4_test.start(x,w);
 r:=public.record_manufactured_output(f,output2_test.payload(y,4)||jsonb_build_object('input_lot',x->>'lot','input_quantity',4),gen_random_uuid());
 e:=output4_test.receive(f,(r->>'entry_id')::uuid);
 r:=output4c_test.publish(x,output4c_test.amendment(x,'reduce'));
 perform late_test.ok(r->>'reconciliation_pending'='true' and (select quantity_available=6 and warehouse_quantity=0 from public.unfinished_lots where id=(x->>'lot')::uuid),'consumed four never restored by Quality');
 perform late_test.ok(private.output_source_held(f,(select entry_id from private.manufactured_outputs where id=(e->>'output')::uuid)),'downstream inspected received source inherits hold');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,output2_test.payload(y,6)||jsonb_build_object('input_lot',x->>'lot','input_quantity',6),gen_random_uuid()),'output_quality_hold');
 perform late_test.ok((select count(*)=1 from public.production_entries where order_id=(w->>'item_id')::uuid),'held processing creates no duplicate entry');

 -- Existing safe compensation is retained when no allocation/dependency blocks.
 x:=output4_test.context('Safe existing compensation');f:=(x->>'factory')::uuid;src:=output4c_test.identify(x);p:=output4c_test.amendment(x,'additional');
 r:=output4c_test.publish(x,p,4);
 perform late_test.ok(r->>'accounting_applied'='true' and private.output_quality(f,(x->>'output')::uuid)->>'revision'='5','existing safe Quality compensation still applies');
 perform late_test.ok((select on_hand=85 from public.finished_goods_balances where factory_id=f) and private.output_stock_free(f,(x->>'product')::uuid,'meter')=85,'only existing five withdrawal occurs, no new receipt');
 perform late_test.ok((select count(*)=1 from private.manufactured_output_adjustments where factory_id=f) and (select count(*)=1 from private.manufactured_output_lots where factory_id=f),'existing ledger and audit reused');

 -- Reservation/hold overlap is not subtracted twice. Commitments stay visible.
 x:=output4_test.context('Reserved held stock');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);src:=output4c_test.identify(x);
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,90,'meter') returning id into sl;
 perform private.reserve_finished(f,sl,90);perform private.source_assign_reservation(f,sl,jsonb_build_array(jsonb_build_object('source_id',src,'quantity','90')));
 r:=output4c_test.publish(x,output4c_test.amendment(x));
 perform late_test.ok((select on_hand=90 and reserved=90 from public.finished_goods_balances where factory_id=f) and (select quantity=90 from public.finished_goods_source_reservations where source_id=src),'held Sales reservations remain unchanged');
 perform late_test.ok(private.output_stock_free(f,(x->>'product')::uuid,'meter')=0,'overlapping held reservation not negative');
 perform late_test.fails(format('select public.source_stock_command(%L,''reserve'',%L,%L,%L)',f,jsonb_build_object('sales_line_id',sl),jsonb_build_array(jsonb_build_object('source_id',src,'quantity','90')),gen_random_uuid()),'output_quality_hold');
 perform late_test.fails(format('select public.source_stock_command(%L,''dispatch'',%L,%L,%L)',f,jsonb_build_object('sales_order',so,'line',sl),jsonb_build_array(jsonb_build_object('source_id',src,'sales_line_id',sl,'quantity','90')),gen_random_uuid()),'output_quality_hold');
 perform late_test.ok((select dispatched_quantity=0 from public.sales_order_lines where id=sl) and (select quantity=90 from public.finished_goods_source_reservations where source_id=src),'denied dispatch rolls back reservation release');
 -- A distinct identified receipt of the same Product is demonstrably safe.
 k:=public.create_production_request(f,'Independent safe source','normal',null,'Separate physical receipt',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',5,'unit','meter')));
 select id into g from public.production_orders where request_id=k;
 perform public.plan_product_item(f,g,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '7 days');perform public.start_product_item(f,g);
 r:=public.record_manufactured_output(f,output2_test.payload(x||jsonb_build_object('item',g),5),gen_random_uuid());
 e:=output4_test.receive(f,(r->>'entry_id')::uuid);
 select id into k from public.finished_goods_sources where factory_id=f and entry_id=(r->>'entry_id')::uuid;
 perform public.source_stock_command(f,'identify',jsonb_build_object('source',k,'quantity','5','label','Separate safe five','physically_identified',true),'[]',gen_random_uuid());
 perform late_test.ok(private.output_stock_free(f,(x->>'product')::uuid,'meter')=5,'held ninety overlapping reserved ninety leaves separate five usable');
 perform public.source_stock_command(f,'adjust',jsonb_build_object('product',x->>'product','unit','meter','quantity','-1','reason','Independent source stock-out'),jsonb_build_array(jsonb_build_object('source_id',k,'quantity','1')),gen_random_uuid());
 perform late_test.ok((select on_hand=94 and reserved=90 from public.finished_goods_balances where factory_id=f) and private.output_stock_free(f,(x->>'product')::uuid,'meter')=4,'unaffected same-Product stock-out remains usable');
 perform set_config('request.jwt.claim.sub',x->>'viewer',false);
 perform late_test.fails(format('select output4c_test.publish(%L,%L,6)',x,output4c_test.amendment(x)),'permission_denied');
 y:=output4_test.context('Other factory');perform set_config('request.jwt.claim.sub',y->>'owner',false);
 perform late_test.fails(format('select output4c_test.publish(%L,%L,6)',x,output4c_test.amendment(x)),'permission_denied');
 perform late_test.ok(not has_function_privilege('authenticated','private.output_apply_or_hold(uuid,uuid,jsonb,bigint,text)','execute') and not has_table_privilege('authenticated','private.manufactured_output_events','insert'),'private helpers and immutable event writes inaccessible');

 x:=output4_test.context('Unidentified pooled hold');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 r:=output4c_test.publish(x,output4c_test.amendment(x));
 perform late_test.ok(private.output_pool_held(f,(x->>'product')::uuid,'meter') and public.finished_source_stock(f,(x->>'product')::uuid,'meter')->>'unattributed_selectable'='0','unidentified affected pool fail closed without guessed genealogy');
 perform late_test.fails(format('select public.adjust_finished_stock(%L,%L,''meter'',-1,''Cannot bypass through pooled client'',%L)',f,x->>'product',gen_random_uuid()),'output_quality_hold');
 perform late_test.fails(format('select public.source_stock_command(%L,''adjust'',%L,%L,%L)',f,jsonb_build_object('product',x->>'product','unit','meter','quantity','-1','reason','Null source selection blocked'),jsonb_build_array(jsonb_build_object('source_id',null,'quantity','1')),gen_random_uuid()),'output_quality_hold');
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f),'unattributed stock-out rollback preserves physical stock');
 insert into public.sales_orders(factory_id,requested_by,created_by,safety_buffer_days,status) values(f,(x->>'owner')::uuid,(x->>'owner')::uuid,0,'approved') returning id into so;
 insert into public.sales_order_lines(factory_id,order_id,product_id,quantity,unit) values(f,so,(x->>'product')::uuid,5,'meter') returning id into sl;
 perform public.receive_warehouse_stock(f,(x->>'product')::uuid,'finished','meter',1,'external_receipt','Controlled supplier receipt','No manufactured Quality gate',gen_random_uuid());
 perform late_test.ok((select on_hand=91 and reserved=0 from public.finished_goods_balances where factory_id=f) and (select count(*)=2 from private.manufactured_output_events where factory_id=f and operation='QUALITY'),'external receipt succeeds once without inspection or unsafe automatic reservation');
 p:=output4c_test.amendment(x);select (value->>'id')::uuid into g from jsonb_array_elements(p->'groups') where value->>'quantity'='5';
 perform late_test.fails(format('select public.receive_manufactured_output(%L,%L,%L,6,%L)',f,x->>'output',jsonb_build_object('group_id',g,'quantity','5','location','No inferred receipt','physical_confirmation',true),gen_random_uuid()),'output_receipt_quantity');

 x:=output4_test.context('Equivalent operation set',true);f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',10);
 p:=jsonb_build_object('groups',(select jsonb_agg(case when value->>'id'=x->>'group' then value||jsonb_build_object('missing_operations',jsonb_build_array(x->>'step2',x->>'step1')) else value end) from jsonb_array_elements(private.output_quality(f,(x->>'output')::uuid)->'groups')),'rejected','0','reason','Equivalent unordered operation evidence');
 r:=output4c_test.publish(x,p);
 perform late_test.ok(not private.output_work_held(f,(w->>'item_id')::uuid),'canonical unordered equivalent set creates no false hold');
 -- Effective package authority uses the same protected Quality command.
 insert into public.permission_packages(factory_id,name,created_by) values(f,'Local Quality amendments',(x->>'owner')::uuid) returning id into k;
 insert into public.permission_package_permissions(factory_id,package_id,module,action) values(f,k,'quality','view'),(f,k,'quality','edit');
 insert into public.member_permission_packages(factory_id,user_id,package_id) values(f,(x->>'worker')::uuid,k);
 perform set_config('request.jwt.claim.sub',x->>'worker',false);
 r:=output4c_test.publish(x,p,6);
 perform late_test.ok(r->>'reconciliation_pending'='true','effective package authorizes Quality finding without Production approval');
 perform set_config('request.jwt.claim.sub',x->>'owner',false);

 x:=output4_test.context('Split classification');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'REPLACE',10);
 p:=jsonb_build_object('groups',(select jsonb_agg(value) from jsonb_array_elements(private.output_quality(f,(x->>'output')::uuid)->'groups') where jsonb_array_length(value->'missing_operations')=0)||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','6','released','6','missing_operations',jsonb_build_array(x->>'step1')),jsonb_build_object('id',gen_random_uuid(),'quantity','4','released','4','missing_operations',jsonb_build_array(x->>'step2'))),'rejected','0','reason','Split inspected unfinished classifications');
 r:=output4c_test.publish(x,p);
 perform late_test.ok(private.output_work_held(f,(w->>'item_id')::uuid) and (select quantity_created=10 from public.unfinished_lots where id=(x->>'lot')::uuid),'replacement entitlement held on split; physical source not split');

 x:=output4_test.context('Unexpected error rollback');f:=(x->>'factory')::uuid;src:=output4c_test.identify(x);p:=output4c_test.amendment(x);
 execute 'create trigger output4c_deliberate_error before insert on public.finished_goods_movements for each row execute function output4c_test.explode()';
 perform late_test.fails(format('select output4c_test.publish(%L,%L,4)',x,p),'fixture_unexpected');
 execute 'drop trigger output4c_deliberate_error on public.finished_goods_movements';
 perform late_test.ok((select on_hand=90 from public.finished_goods_balances where factory_id=f) and (select count(*)=1 from private.manufactured_output_events where factory_id=f and operation='QUALITY'),'unexpected SQL error never committed as pending success');
end$$;
select count(*) assertions from late_test.checks;
rollback;
