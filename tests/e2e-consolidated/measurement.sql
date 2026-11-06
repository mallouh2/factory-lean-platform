begin;
truncate late_test.checks;
create schema if not exists measurement_test;
create or replace function measurement_test.fixture(label text,ended boolean) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;p uuid;l uuid;m uuid;cat uuid;so uuid;i uuid;r jsonb;begin
 select a.x into x from public.local_e2e_context a;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 insert into public.production_lines(factory_id,name,code) values(f,'Measurement '||label,'MEAS-'||label) returning id into l;
 insert into public.work_center_categories(factory_id,name) values(f,'Measurement '||label) returning id into cat;
 insert into public.work_centers(factory_id,name,code,line_id,category_id,status,dependency_mode,impact_scope) values(f,'Measurement machine '||label,'MEAS-'||label,l,cat,'running','blocking','whole_line') returning id into m;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Measurement pipe '||label,'MEAS-'||label,'meter','meter',.5) returning id into p;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes) values(f,m,p,6000,'meter',0);
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,p,1,'work_center',m);
 so:=public.create_sales_order(f,jsonb_build_object('customer_reference','Measurement acceptance '||label,'requested_delivery',clock_timestamp()+interval '4 days','lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',60,'unit','meter'))),gen_random_uuid());
 perform public.approve_sales_order(f,so,gen_random_uuid());select id into i from public.production_orders where factory_id=f and product_id=p;
 perform public.plan_product_item(f,i,l,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');perform public.start_product_item(f,i);
 x:=x||jsonb_build_object('item',i,'line',l,'machine',m,'product',p,'sales',so);
 r:=public.record_manufactured_output(f,output2_test.payload(x,60),gen_random_uuid());
 if ended then perform public.finish_product_item(f,i);end if;
 return x||jsonb_build_object('entry',r->>'entry_id','output',(select id from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid));
end$$;
create or replace function measurement_test.quality(x jsonb,total numeric,accepted numeric,rejected numeric default 0) returns jsonb language plpgsql as $$
declare h private.manufactured_outputs;g jsonb;begin
 select * into h from private.manufactured_outputs where id=(x->>'output')::uuid;
 g:=case when accepted>0 then jsonb_build_array(h.recorded_groups->0||jsonb_build_object('quantity',accepted::text,'released',accepted::text)) else '[]'::jsonb end;
 return public.manufactured_output_command(h.factory_id,'QUALITY',h.id,jsonb_build_object('groups',g,'total',total::text,'rejected',rejected::text,'actual_rejected_kg',case when rejected>0 then '0.8' else '0' end,'reason','Measured total verified during controlled acceptance'),1,gen_random_uuid());
end$$;
create or replace function measurement_test.receive(x jsonb,q numeric) returns jsonb language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;o uuid:=(x->>'output')::uuid;g jsonb;w uuid;revision bigint;begin
 select id into w from public.factory_warehouses where factory_id=f and active and storage_class='FINISHED' limit 1;
 if w is null then raise exception 'Existing finished warehouse fixture required';end if;
 select value into g from jsonb_array_elements(private.output_quality(f,o)->'groups') where jsonb_array_length(value->'missing_operations')=0 limit 1;
 select max(e.revision) into revision from private.manufactured_output_events e where output_id=o;
 return public.receive_manufactured_output(f,o,jsonb_build_object('group_id',g->>'id','quantity',q::text,'warehouse_id',w,'physical_confirmation',true,'note','Controlled identified source'),revision,gen_random_uuid());
end$$;

do $$declare x jsonb;f uuid;i uuid;before_jobs bigint;r jsonb;y jsonb;begin
 x:=measurement_test.fixture('active',false);f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 select count(*) into before_jobs from public.production_orders where factory_id=f;
 perform measurement_test.quality(x,58,58);
 perform late_test.ok((select quality_measurement_delta=2 and good_quantity=60 and fulfillment_good_quantity=58 and accepted_remaining_quantity=2 from public.production_orders where id=i),'active: preserve gross60, actual58, ordinary remaining2');
 perform late_test.ok((select target_quantity=60 from public.production_orders where id=i),'original demand remains60');
 perform late_test.ok((select count(*) from public.production_orders where factory_id=f)=before_jobs,'Quality correction creates no production work');
 perform late_test.ok((public.production_compensation_read(f,(x->>'output')::uuid)#>>'{distribution,eligible}')='0','recording error grants no rejected/unfinished allowance');
 perform late_test.ok((public.production_compensation_read(f,(x->>'output')::uuid)#>>'{measurement,blocked_reason}')='CONTINUE_ORIGINAL','active measurement shortage continues ordinary work');
 perform late_test.ok(private.quality_production_remaining(f,i)=60,'active forecast58+ordinary remaining2, not58 or62');
 perform measurement_test.receive(x,58);
 perform late_test.ok((select on_hand=58 and reserved=58 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid),'58 received/reserved once');
 r:=public.record_manufactured_output(f,output2_test.payload(x,2)-'confirm_overproduction',gen_random_uuid());
 y:=x||jsonb_build_object('entry',r->>'entry_id','output',(select id from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid));
 perform late_test.ok((select good_quantity=62 and quality_measurement_delta=2 and fulfillment_good_quantity=60 and accepted_remaining_quantity=0 from public.production_orders where id=i),'ordinary2 succeeds without recovery/overproduction allowance; net60');
 perform measurement_test.quality(y,2,2);perform measurement_test.receive(y,2);
 perform late_test.ok((select on_hand=60 and reserved=60 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid),'Sales-linked stock conserved at60, no double credit');
 perform late_test.ok((select sum(quantity)=0 and sum(received_quantity)=60 from public.sales_incoming_allocations where factory_id=f and item_id=i),'incoming converts to reservations exactly60');
 perform late_test.ok((select original_scrap_kg=0 and effective_scrap_kg=0 and good_quantity=60 from public.production_entries where id=(x->>'entry')::uuid),'original entry and Scrap KG untouched');
end$$;

do $$declare x jsonb;f uuid;i uuid;r jsonb;again jsonb;payload jsonb;k uuid:=gen_random_uuid();revision bigint;before_jobs bigint;child uuid;y jsonb;member uuid;begin
 x:=measurement_test.fixture('ended',true);f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 perform measurement_test.quality(x,58,58);perform measurement_test.receive(x,58);
 select count(*) into before_jobs from public.production_orders where factory_id=f;
 select max(e.revision) into revision from private.manufactured_output_events e where output_id=(x->>'output')::uuid;
 perform late_test.ok((public.production_compensation_read(f,(x->>'output')::uuid)#>>'{measurement,available}')='2','ended execution exposes unproduced make-up2');
 perform late_test.ok((select count(*) from public.production_orders where factory_id=f)=before_jobs,'ended shortage never automatically creates work');
 payload:=jsonb_build_object('quantity','2','recording_complete_confirmation',true);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform late_test.fails(format('select public.plan_measurement_makeup(%L,%L,%L,%s,%L)',f,x->>'output',payload,revision,k),'42501');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 r:=public.plan_measurement_makeup(f,(x->>'output')::uuid,payload,revision,k);child:=(r->>'item_id')::uuid;
 again:=public.plan_measurement_makeup(f,(x->>'output')::uuid,payload,revision,k);perform late_test.ok(again=r,'make-up UUID replay returns same job');
 perform late_test.ok((select count(*) from public.production_orders where factory_id=f)=before_jobs+1,'one explicitly created make-up item');
 perform late_test.ok((select source_kind='MEASUREMENT' and mode='PLANNED' and quantity=2 from private.production_compensation where factory_id=f and id=k),'distinct measurement allocation, never rejected recovery');
 perform late_test.ok((select group_id is null and lot_id is null and material_request_id is null from private.manufactured_completion_work where factory_id=f and item_id=child),'no WIP/material allocation granted');
 perform late_test.ok((select replacement_original_item_id=i and target_quantity=2 and status='planned' from public.production_orders where id=child),'linked unscheduled ordinary make-up2');
 perform late_test.fails(format('select public.plan_measurement_makeup(%L,%L,%L,%s,%L)',f,x->>'output',payload,revision,gen_random_uuid()),'40001');
 perform late_test.ok(private.quality_production_remaining(f,i,true)=2,'original incoming commitment covered once by linked work');
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',f,output2_test.payload(x,2),gen_random_uuid()),'40001');
 perform late_test.ok((select count(*) from public.production_entries where order_id=i)=1,'committed make-up blocks positive recording on ended source');
 perform late_test.ok(not has_function_privilege('authenticated','private.measurement_makeup_state(uuid,uuid,jsonb)','EXECUTE'),'private measurement helper not directly callable');

 perform public.plan_product_item(f,child,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 2 hours');perform public.start_product_item(f,child);
 y:=x||jsonb_build_object('item',child);r:=public.record_manufactured_output(f,output2_test.payload(y,2),gen_random_uuid());
 y:=y||jsonb_build_object('entry',r->>'entry_id','output',(select id from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid));
 perform measurement_test.quality(y,2,2);perform measurement_test.receive(y,2);
 perform late_test.ok((select fulfillment_good_quantity=60 and accepted_remaining_quantity=0 and target_quantity=60 from public.production_orders where id=i),'linked Good fulfills original demand exactly once');
 perform late_test.ok(public.production_recording_progress(f,i)->>'ordinary_remaining'='0','completed source shows zero remaining after linked accepted Good');
 perform late_test.ok((select on_hand=60 and reserved=60 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid),'linked receipt conserves Sales reservation and physical stock60');
 perform late_test.ok((select sum(quantity)=0 and sum(received_quantity)=60 from public.sales_incoming_allocations where factory_id=f and item_id=i),'linked receipt consumes original Sales commitment exactly once');
 perform late_test.ok((select original_scrap_kg=0 and effective_scrap_kg=0 and good_quantity=60 from public.production_entries where id=(x->>'entry')::uuid),'ended original Good/Scrap evidence unchanged');
end$$;
do $$declare x jsonb;f uuid;i uuid;h private.manufactured_outputs;q jsonb;g jsonb;op uuid;other uuid;begin
 x:=measurement_test.fixture('mixed',false);f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 select * into h from private.manufactured_outputs where id=(x->>'output')::uuid;select id into op from public.production_routing_steps where factory_id=f and product_id=h.product_id limit 1;
 g:=jsonb_build_array(h.recorded_groups->0||jsonb_build_object('quantity','48','released','48'),h.recorded_groups->0||jsonb_build_object('id',gen_random_uuid(),'quantity','10','released','10','missing_operations',jsonb_build_array(op)));
 perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'total','58','rejected','0','actual_rejected_kg','0','reason','Measured actual58 with10 unfinished'),1,gen_random_uuid());
 perform late_test.ok((select good_quantity=60 and quality_measurement_delta=2 and quality_output_good_delta=12 and fulfillment_good_quantity=48 from public.production_orders where id=i),'measurement2 and unfinished10 remain distinct, accepted48');
 perform late_test.ok(private.ordinary_output_remaining(f,i)=2,'only unproduced2 ordinary; unfinished10 never regranted as ordinary');
 perform late_test.ok((public.production_compensation_read(f,h.id)->>'available')::numeric=10,'unfinished entitlement10 excludes measurement2');
 perform late_test.ok(private.quality_production_remaining(f,i)=50,'accepted48 plus unproduced2; unfinished not falsely finished');
 select id into other from public.factories where id<>f limit 1;if other is null then raise exception 'Known cross-factory fixture required';end if;
 perform late_test.fails(format('select public.plan_measurement_makeup(%L,%L,%L,2,%L)',other,h.id,jsonb_build_object('quantity','2','recording_complete_confirmation',true),gen_random_uuid()),'42501');
 perform late_test.fails(format('select public.production_recording_progress(%L,%L)',other,i),'42501');
end$$;
do $$declare x jsonb;f uuid;i uuid;o uuid;begin
 x:=measurement_test.fixture('rejection',false);f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;o:=(x->>'output')::uuid;
 perform measurement_test.quality(x,60,58,2);
 perform late_test.ok((select quality_measurement_delta=0 and quality_output_good_delta=2 and fulfillment_good_quantity=58 from public.production_orders where id=i),'actual60 rejection2 has no measurement shortage');
 perform late_test.ok(private.ordinary_output_remaining(f,i)=0,'rejected material never becomes ordinary unproduced work');
 perform late_test.ok((public.production_compensation_read(f,o)->>'available')::numeric=2,'existing rejected recovery2 preserved');
 perform late_test.ok((public.production_compensation_read(f,o)#>>'{measurement,source_shortage}')='0','rejection grants zero measurement allowance');
end$$;
do $$declare x jsonb;f uuid;pkg uuid;who uuid;makeup_result jsonb;begin
 x:=measurement_test.fixture('package',true);f:=(x->>'factory')::uuid;who:=(x->>'worker')::uuid;perform measurement_test.quality(x,58,58);
 insert into public.permission_packages(factory_id,name) values(f,'Measurement make-up test package') returning id into pkg;
 insert into public.permission_package_permissions(factory_id,package_id,module,action) select f,pkg,'orders',unnest(array['view','edit','create','approve']);
 insert into public.member_permission_packages(factory_id,user_id,package_id) values(f,who,pkg);
 perform set_config('request.jwt.claim.sub',who::text,true);
 makeup_result:=public.plan_measurement_makeup(f,(x->>'output')::uuid,'{"quantity":"2","recording_complete_confirmation":true}',2,gen_random_uuid());
 perform late_test.ok(makeup_result->>'source_kind'='MEASUREMENT','effective package permissions authorize explicit make-up');
 perform late_test.ok((select created_by=who from private.production_compensation where id=(makeup_result->>'compensation_id')::uuid),'actual engineer actor retained, no owner impersonation');
 perform late_test.ok((select target_quantity=60 and good_quantity=60 and fulfillment_good_quantity=58 from public.production_orders where id=(x->>'item')::uuid),'make-up allocation never changes original target or accepted output');
end$$;
do $$declare x jsonb;f uuid;r jsonb;begin
 x:=measurement_test.fixture('already-recorded',true);f:=(x->>'factory')::uuid;perform measurement_test.quality(x,58,58);
 r:=public.record_manufactured_output(f,output2_test.payload(x,2),gen_random_uuid());
 perform late_test.ok((public.production_compensation_read(f,(x->>'output')::uuid)#>>'{measurement,available}')='0','subsequent real output awaiting inspection prevents duplicate make-up');
 perform late_test.fails(format('select public.plan_measurement_makeup(%L,%L,%L,2,%L)',f,x->>'output','{"quantity":"2","recording_complete_confirmation":true}',gen_random_uuid()),'40001');
 perform late_test.ok((select target_quantity=60 and fulfillment_good_quantity=60 from public.production_orders where id=(x->>'item')::uuid),'same-shift finished recording before allocation conserves ordinary demand');
end$$;
select count(*) as checks from late_test.checks;
rollback;
