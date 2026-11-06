-- Disposable full-app fixture only. All synthetic transactions are rolled back.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback fixture required';end if;
end$$;
select set_config('history.test.context',(select x::text from local_preview.context),true);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'FAIL: %',label;end if;raise notice 'PASS: %',label;
end$$;
do $$declare x jsonb:=current_setting('history.test.context')::jsonb;f uuid:=(x->>'factory')::uuid;e uuid:=(x->>'entry')::uuid;
 p jsonb;expected numeric;total jsonb;pending jsonb;rejected jsonb;applied jsonb;g numeric;w numeric;before_stock numeric;
begin
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 select sum(effective_scrap_kg) into expected from public.production_entries where factory_id=f and order_id=(x->>'item')::uuid;
 perform pg_temp.ok((public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'all current official entries, not selected entry only');
 select on_hand into before_stock from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid and unit='meter';
 -- More than one legacy History page, using the existing writer and normal active work.
 p:=jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',x->>'technician','good',1,'scrap_kg',.1,'discarded_quantity',0);
 for i in 1..51 loop perform public.record_lean_production(f,p,gen_random_uuid());end loop;
 expected:=expected+5.1;
 perform pg_temp.ok((public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'aggregate includes records beyond page 1');
 select effective_good,effective_unfinished into g,w from public.production_entries where id=e;
 p:=jsonb_build_object('entry',e,'good',g::text,'discarded_quantity','0','scrap_kg','0.1234567890123456789','unfinished',w::text,
 'remaining_work','Finish cooling','reason','Measured Scrap again for local reader test','expected_revision',(select count(*) from public.production_entry_corrections where entry_id=e),'allocations','[]'::jsonb);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 pending:=public.production_correction_command(f,'submit',p,gen_random_uuid());
 perform pg_temp.ok(pending->>'status'='PENDING' and (public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'pending correction has no effect');
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 rejected:=public.production_correction_command(f,'reject',jsonb_build_object('id',pending->>'id','reason','Not the agreed measurement'),gen_random_uuid());
 perform pg_temp.ok(rejected->>'status'='REJECTED' and (public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'rejected correction has no effect');
 select expected-effective_scrap_kg+.1234567890123456789 into expected from public.production_entries where id=e;
 applied:=public.production_correction_command(f,'submit',p,gen_random_uuid());
 perform pg_temp.ok(applied->>'status'='APPROVED' and (public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'approved correction affects official total exactly once with full precision');
 perform public.production_correction_command(f,'approve',jsonb_build_object('id',applied->>'id'),gen_random_uuid());
 perform pg_temp.ok((public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=expected,'approval retry cannot duplicate Scrap');
 perform pg_temp.ok(public.production_history_product_scrap(f,gen_random_uuid())->'scrap_kg'='null'::jsonb,'missing evidence is not zero');
 perform pg_temp.ok((select on_hand=before_stock+51 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid and unit='meter'),'reader and Scrap-only corrections do not post Good inventory');
end$$;
-- Separate synthetic resources; no existing queue or configuration is changed.
do $$declare x jsonb;f uuid;p2 uuid;r uuid;a uuid;b uuid;e uuid;tech uuid;second_machine uuid;p jsonb;begin
 x:=mp_test.fixture('history-product-scope');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'History aggregate regression','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Other product','OTHER','meter','meter',.5) returning id into p2;
 select id into second_machine from public.work_centers where factory_id=f and line_id=(x->>'other_line')::uuid;
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 perform public.configure_center_capabilities(f,second_machine,jsonb_build_array(jsonb_build_object('product_id',p2,'rate',6000,'rate_unit','meter','setup_minutes',0)));
 r:=public.create_production_request(f,'Two product order','normal',null,'Rollback-only fixture',jsonb_build_array(
 jsonb_build_object('product_id',x->>'product','quantity',1,'unit','meter'),jsonb_build_object('product_id',p2,'quantity',1,'unit','meter')));
 select id into a from public.production_orders where request_id=r and product_id=(x->>'product')::uuid;
 select id into b from public.production_orders where request_id=r and product_id=p2;
 select id into tech from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 perform public.plan_product_item(f,a,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days');
 perform public.plan_product_item(f,b,(x->>'other_line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days');
 perform public.start_product_item(f,a);perform public.start_product_item(f,b);
 perform public.change_status(f,(x->>'machine')::uuid,'running');perform public.change_status(f,second_machine,'running');
 p:=jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',a,'technician',tech,'good',1,'scrap_kg',15,'discarded_quantity',0);
 e:=(public.record_lean_production(f,p,gen_random_uuid())->>'entry_id')::uuid;
 perform public.record_lean_production(f,p||jsonb_build_object('production_unit',x->>'other_line','item',b,'scrap_kg',8),gen_random_uuid());
 perform pg_temp.ok((public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=15,'Product A is 15 KG, not 23 KG from both products');
 perform public.finish_product_item(f,a);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '3 days');
 perform public.start_product_item(f,(x->>'item')::uuid);
 perform public.record_lean_production(f,p||jsonb_build_object('item',x->>'item','scrap_kg',90),gen_random_uuid());
 perform pg_temp.ok((public.production_history_product_scrap(f,e)->>'scrap_kg')::numeric=15,'same product in a different order is excluded');
end$$;
set local role authenticated;
do $$declare x jsonb:=current_setting('history.test.context')::jsonb;f uuid:=(x->>'factory')::uuid;begin
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform pg_temp.ok(jsonb_typeof(public.production_history_product_scrap(f,(x->>'entry')::uuid)->'scrap_kg')='string','actual authenticated role, RLS and exact string transport');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);
 begin perform public.production_history_product_scrap(f,(x->>'entry')::uuid);raise exception 'Denial missing';exception when insufficient_privilege then raise notice 'PASS: denied user cannot read aggregate';end;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 begin perform public.production_history_product_scrap(gen_random_uuid(),(x->>'entry')::uuid);raise exception 'Isolation missing';exception when insufficient_privilege then raise notice 'PASS: foreign factory cannot read aggregate';end;
end$$;
reset role;
select pg_temp.ok(not has_function_privilege('anon','public.production_history_product_scrap(uuid,uuid)','execute'),'anonymous execution revoked');
rollback;
