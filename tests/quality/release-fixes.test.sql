-- All fixtures are synthetic and rolled back in the disposable loopback cluster.
begin;
create function pg_temp.q_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Quality release assertion: %',label;end if;raise notice 'PASS %',label;
end$$;
create function pg_temp.q_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;set constraints quality_entry_weight_check immediate;set constraints quality_entry_weight_check deferred;
 exception when others then if sqlerrm=expected then raise notice 'PASS blocked %',expected;return;end if;
 raise exception 'Expected %, got %',expected,sqlerrm;end;raise exception 'Expected failure %',expected;
end$$;
create function pg_temp.identify(f uuid,e uuid,q numeric) returns uuid language plpgsql as $$declare s uuid;begin
 select id into s from public.finished_goods_sources where factory_id=f and entry_id=e;
 perform public.source_stock_command(f,'identify',jsonb_build_object('source',s,'quantity',q::text,'label','RELEASE-'||s,'physically_identified',true),'[]',gen_random_uuid());return s;
end$$;
do $$declare x quality_test.fixtures;s uuid;r uuid;q uuid;lot uuid;mr uuid;rev integer;e uuid;rework_source uuid;p jsonb;retry uuid;result uuid;child uuid;grandchild uuid;child_entry uuid;child_q uuid;so uuid;sl uuid;data jsonb;other uuid;before_commands integer;begin
 perform quality_test.make_fixture('release-rework','piece',.25,100);select * into x from quality_test.fixtures where name='release-rework';
 s:=pg_temp.identify(x.factory_id,x.entry_id,100);select id into r from public.quality_reasons where factory_id=x.factory_id and not is_other limit 1;
 q:=public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity','10','reason',r,'disposition','REWORK','physically_identified',true),gen_random_uuid());
 select lot_id into lot from public.quality_rejections where id=q;
 mr:=public.quality_command(x.factory_id,'request_rework',jsonb_build_object('rejection',q,'lot',lot,'quantity','10'),gen_random_uuid());
 select revision into rev from public.material_requests where id=mr;
 perform public.supply_command(x.factory_id,'material_change',jsonb_build_object('id',mr,'revision',rev,'action','issue'),gen_random_uuid());
 e:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',x.item_id,'technician',x.technician_id,'good',10,'discarded_quantity',0,'scrap_kg',0,'unfinished',0,'input_lot',lot,'input_quantity',10),gen_random_uuid())->>'id')::uuid;
 set constraints quality_entry_weight_check immediate;set constraints quality_entry_weight_check deferred;
 rework_source:=pg_temp.identify(x.factory_id,e,10);
 retry:=gen_random_uuid();p:=jsonb_build_object('entry',e,'good',7,'discarded_quantity',3,'scrap_kg','0.75','unfinished',0,'reason','Recounted failed rework');
 result:=public.source_stock_command(x.factory_id,'correct',p,jsonb_build_array(jsonb_build_object('source_id',rework_source,'quantity','3')),retry);
 set constraints quality_entry_weight_check immediate;set constraints quality_entry_weight_check deferred;
 perform pg_temp.q_assert((select effective_good=7 and effective_scrap=3 and effective_scrap_kg=.75 and original_scrap_kg=0 from public.production_entries where id=e),'QV-01 exact zero-to-positive correction validates final KG');
 perform pg_temp.q_assert((select previous_good=10 and corrected_good=7 and previous_scrap_kg=0 and corrected_scrap_kg=.75 from public.production_entry_corrections where entry_id=e),'QV-01 original and correction audit preserved');
 perform pg_temp.q_assert((select on_hand=97 from public.finished_goods_balances where factory_id=x.factory_id) and (select quantity_available=7 from public.finished_goods_sources where id=rework_source) and (select quantity_available=0 from public.unfinished_lots where id=lot),'QV-01 stock/source/WIP conservation');
 perform pg_temp.q_assert(public.source_stock_command(x.factory_id,'correct',p,jsonb_build_array(jsonb_build_object('source_id',rework_source,'quantity','3')),retry)=result and (select count(*)=1 from public.production_entry_corrections where entry_id=e) and (select count(*)=1 from public.finished_goods_movements where entry_id=e and kind='production_correction'),'QV-01 retry has one correction and one Good debit');
 select count(*) into before_commands from public.fulfillment_commands where factory_id=x.factory_id;
 perform pg_temp.q_error(format('select public.correct_lean_production(%L,%L::jsonb,gen_random_uuid())',x.factory_id,(p||jsonb_build_object('scrap_kg',0,'reason','Invalid zero mass'))::text),'quality_weight');
 perform pg_temp.q_assert((select effective_good=7 and effective_scrap_kg=.75 from public.production_entries where id=e) and (select count(*)=1 from public.production_entry_corrections where entry_id=e) and (select count(*)=before_commands from public.fulfillment_commands where factory_id=x.factory_id),'QV-01 invalid mass rolls back entry, audit and retry records');
 perform pg_temp.q_assert(private.quality_gap(x.factory_id,q)=3 and (select sum(stock_delta)=97 from public.finished_goods_movements where factory_id=x.factory_id),'QV-01 no duplicate Scrap/Good/WIP effect');

 perform quality_test.make_fixture('release-projection','meter',.35,100,0,true);select * into x from quality_test.fixtures where name='release-projection';
 update public.production_orders set target_quantity=100 where id=x.item_id;
 s:=pg_temp.identify(x.factory_id,x.entry_id,100);select id into r from public.quality_reasons where factory_id=x.factory_id and not is_other limit 1;
 q:=public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity','10','reason',r,'disposition','SCRAP','actual_scrap_kg','3.5','physically_identified',true),gen_random_uuid());
 perform pg_temp.q_assert((select incoming=10 and projected=100 and on_hand=90 from private.finished_inventory_projection(x.factory_id) where product_id=x.product_id),'QV-02 shared projection uses accepted active remaining');
 select z into data from private.warehouse_inventory_rows(x.factory_id) z where z->>'id'=x.product_id::text;
 perform pg_temp.q_assert((data->>'incoming')::numeric=0 and (data->>'in_production')::numeric=10 and (data->>'projected')::numeric=100,'QV-02 Warehouse active split has no negative Incoming');
 data:=public.warehouse_page(x.factory_id,1);
 perform pg_temp.q_assert((data->'rows'->0->>'incoming')::numeric=10 and (data->'rows'->0->>'projected')::numeric=100,'QV-02 existing Warehouse commitments reader shares accepted forecast');
 -- Actual Sales approval consumes 90 on-hand and promises the remaining 10 from the active original item.
 so:=public.create_sales_order(x.factory_id,jsonb_build_object('lines',jsonb_build_array(jsonb_build_object('product_id',x.product_id,'quantity',100,'unit','meter'))));
 perform public.approve_sales_order(x.factory_id,so);select id into sl from public.sales_order_lines where order_id=so;
 perform pg_temp.q_assert((select quantity=10 from public.sales_incoming_allocations where line_id=sl and item_id=x.item_id) and (select reserved=90 from public.finished_goods_balances where factory_id=x.factory_id),'QV-02 accepted future Sales commitment');
 child:=public.quality_command(x.factory_id,'replacement',jsonb_build_object('rejection',q,'quantity','10'),gen_random_uuid());
 perform pg_temp.q_assert(private.quality_production_remaining(x.factory_id,x.item_id)=0 and private.quality_production_remaining(x.factory_id,child)=10 and (select incoming=10 and projected=0 from private.finished_inventory_projection(x.factory_id) where product_id=x.product_id),'QV-02 linked replacement forecast counted once after Sales commitments');
 perform pg_temp.q_assert((select quantity=0 and received_quantity=0 and released_quantity=0 from public.sales_incoming_allocations where line_id=sl and item_id=x.item_id) and (select quantity=10 from public.sales_incoming_allocations where line_id=sl and item_id=child) and (select sum(quantity)=10 from public.sales_incoming_allocations where line_id=sl),'QV-02 Sales promise follows corrective source without changing totals/history');
 select z into data from private.warehouse_inventory_rows(x.factory_id) z where z->>'id'=x.product_id::text;
 perform pg_temp.q_assert((data->>'incoming')::numeric=10 and (data->>'in_production')::numeric=0,'QV-02 planned replacement replaces active gap in Warehouse split');
 data:=private.sales_order_detail(x.factory_id,so);
 perform pg_temp.q_assert((data->'lines'->0->>'incoming_quantity')::numeric=10 and (data->'lines'->0->>'reserved_quantity')::numeric=90,'QV-02 Sales forecast reader preserves commitment split');
 data:=public.fulfillment_production_context(x.factory_id,child);
 perform pg_temp.q_assert((data->'rows'->0->>'incoming_allocated')::numeric=10,'QV-02 Production reader retains corrective Sales link');
 perform pg_temp.q_error(format('select public.quality_command(%L,''replacement'',%L::jsonb,gen_random_uuid())',x.factory_id,jsonb_build_object('rejection',q,'quantity','1')::text),'quality_shortfall');
 perform public.finish_product_item(x.factory_id,x.item_id);
 update public.production_orders set line_id=x.line_id,start_time=now(),expected_finish=now()+interval '1 hour' where id=child;
 perform public.start_product_item(x.factory_id,child);
 child_entry:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',child,'technician',x.technician_id,'good',10,'discarded_quantity',0,'scrap_kg',0,'unfinished',0,'input_quantity',0),gen_random_uuid())->>'id')::uuid;
 perform pg_temp.q_assert((select on_hand=100 and reserved=100 from public.finished_goods_balances where factory_id=x.factory_id) and (select quantity=0 and received_quantity=10 from public.sales_incoming_allocations where line_id=sl and item_id=child) and (select incoming=0 and projected=0 from private.finished_inventory_projection(x.factory_id) where product_id=x.product_id),'QV-02 corrective receipt fulfills Sales commitment exactly once');
 perform pg_temp.q_assert((select good_quantity=100 and accepted_good_quantity=90 and fulfillment_good_quantity=100 from public.production_orders where id=x.item_id),'QV-02 gross original production stays separate');
 -- Release the Sales reservation before rejecting physically identified corrective stock.
 perform public.change_sales_order(x.factory_id,so,'{"cancel":true}','Customer cancelled',gen_random_uuid());
 s:=pg_temp.identify(x.factory_id,child_entry,10);
 child_q:=public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity','3','reason',r,'disposition','SCRAP','actual_scrap_kg','1.05','physically_identified',true),gen_random_uuid());
 grandchild:=public.quality_command(x.factory_id,'replacement',jsonb_build_object('rejection',child_q,'quantity','3'),gen_random_uuid());
 perform pg_temp.q_assert(private.quality_production_remaining(x.factory_id,child)=0 and private.quality_production_remaining(x.factory_id,grandchild)=3 and (select incoming=3 from private.finished_inventory_projection(x.factory_id) where product_id=x.product_id),'QV-02 nested corrective work counted once through completed ancestor');
 update public.production_orders set status='cancelled' where id=grandchild;
 perform public.finish_product_item(x.factory_id,child);
 perform public.quality_command(x.factory_id,'replacement',jsonb_build_object('rejection',q,'quantity','3'),gen_random_uuid());
 perform pg_temp.q_error(format('select public.quality_command(%L,''replacement'',%L::jsonb,gen_random_uuid())',x.factory_id,jsonb_build_object('rejection',child_q,'quantity','3')::text),'quality_shortfall');
 perform pg_temp.q_assert((select incoming=3 from private.finished_inventory_projection(x.factory_id) where product_id=x.product_id),'QV-02 another branch cannot duplicate the same root recovery');

 insert into public.quality_reasons(factory_id,name,name_ar,active) select x.factory_id,'Reason '||lpad(n::text,3,'0'),'سبب '||lpad(n::text,3,'0'),true from generate_series(1,105)n;
 insert into public.quality_reasons(factory_id,name,active) select x.factory_id,'AAA archived '||n,false from generate_series(1,110)n;
 select id into other from public.quality_reasons where factory_id=x.factory_id and is_other;
 data:=public.quality_read(x.factory_id,'{"mode":"reasons","active_only":"true","page":1}');
 perform pg_temp.q_assert((data->>'total')::integer=113 and jsonb_array_length(data->'rows')=101 and exists(select 1 from jsonb_array_elements(data->'rows')choice where choice->>'id'=other::text) and not exists(select 1 from jsonb_array_elements(data->'rows')choice where choice->>'active'='false'),'QV-03 first 100 active ordinary reasons plus permanent Other; archives excluded');
 data:=public.quality_read(x.factory_id,'{"mode":"reasons","active_only":"true","page":2}');
 perform pg_temp.q_assert(jsonb_array_length(data->'rows')=14 and exists(select 1 from jsonb_array_elements(data->'rows')choice where choice->>'id'=other::text),'QV-03 next active page retains Other');
 data:=public.quality_read(x.factory_id,'{"mode":"reasons","active_only":"true","search":"سبب 105"}');
 perform pg_temp.q_assert((data->>'total')::integer=1 and jsonb_array_length(data->'rows')=2,'QV-03 Arabic search plus Other');
 data:=public.quality_read(x.factory_id,jsonb_build_object('mode','reasons','active_only','true','search','Reason 105','selected',r));
 perform pg_temp.q_assert((data->>'total')::integer=1 and jsonb_array_length(data->'rows')=3,'QV-03 English search preserves previously selected active reason');
 perform pg_temp.q_error(format('select public.quality_command(%L,''reason'',%L::jsonb,gen_random_uuid())',x.factory_id,jsonb_build_object('id',other,'name','Other','active',false)::text),'quality_reason');
 perform pg_temp.q_assert((select active from public.quality_reasons where id=other) and (select reason is not null and reason_ar is not null from public.quality_rejections where id=q),'QV-03 permanent Other and historical reason snapshots protected');
 set constraints all immediate;
end$$;
rollback;
