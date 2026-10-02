-- TESTING only. Every fixture, quantity, configuration and audit change rolls back.
begin;
do $test$
declare f uuid;actor uuid;tech uuid;product uuid;product2 uuid;line1 uuid;line2 uuid;machine uuid;normal uuid;
 request uuid;item uuid;other_item uuid;entry uuid;lot uuid;partial uuid;child uuid;retry uuid:=gen_random_uuid();
 result jsonb;before_history jsonb;before_centers jsonb;plan_before jsonb;stmt text;expected text;caught boolean;i int;only_wip uuid;correction_retry uuid;
begin
 select m.factory_id,m.user_id,m.id into f,actor,tech from public.memberships m join public.factories fac on fac.id=m.factory_id
 where fac.is_demo and m.status='approved' and private.has_permission(m.factory_id,'orders','edit') limit 1;
 -- SQL tools run as admin; derive the existing authorized TESTING actor explicitly.
 if f is null then
 select m.factory_id,m.user_id,m.id into f,actor,tech from public.memberships m join public.factories fac on fac.id=m.factory_id
 where fac.is_demo and m.status='approved' and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id and p.user_id=m.user_id and p.module='orders' and p.action='edit') limit 1;end if;
 if f is null then raise exception 'existing TESTING actor required';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select jsonb_agg(to_jsonb(e) order by id) into before_history from public.production_entries e where factory_id=f;
 select jsonb_agg(to_jsonb(c) order by id) into before_centers from public.work_centers c where factory_id=f;
 update public.production_shifts set archived=true where factory_id=f and not archived;
 insert into public.products(factory_id,name,code,unit) values(f,'WIP QA pipe','WIP-'||substr(gen_random_uuid()::text,1,8),'piece') returning id into product;
 insert into public.products(factory_id,name,code,unit) values(f,'WIP QA unrelated','WIP-'||substr(gen_random_uuid()::text,1,8),'piece') returning id into product2;
 insert into public.production_lines(factory_id,name,code) values(f,'WIP QA source','WIP-'||substr(gen_random_uuid()::text,1,8)) returning id into line1;
 insert into public.production_lines(factory_id,name,code) values(f,'WIP QA secondary','WIP-'||substr(gen_random_uuid()::text,1,8)) returning id into line2;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'WIP QA source machine','WIP-'||substr(gen_random_uuid()::text,1,8),line1,category_id from public.work_centers where factory_id=f and category_id is not null limit 1 returning id into normal;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,normal,product,100,'piece');
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode)
 select f,'WIP QA independent','WIP-'||substr(gen_random_uuid()::text,1,8),null,category_id,'independent' from public.work_centers where id=normal returning id into machine;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,machine,product,100,'piece');
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'WIP QA secondary machine','WIP-'||substr(gen_random_uuid()::text,1,8),line2,category_id from public.work_centers where id=normal;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
 select f,id,product,100,'piece' from public.work_centers where line_id=line2;
 request:=public.create_production_request(f,'WIP QA request','normal',null,'QA internal production reason',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1000,'unit','piece'),jsonb_build_object('product_id',product2,'quantity',1000,'unit','piece')));
 select id into item from public.production_orders where request_id=request and product_id=product;
 select id into other_item from public.production_orders where request_id=request and product_id=product2;
 update public.production_orders set line_id=line1,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=item;
 perform public.start_product_item(f,item);
 select jsonb_build_array(line_id,start_time,expected_finish,actual_start,status) into plan_before from public.production_orders where id=item;
 entry:=public.record_production(f,'line',line1,item,tech,600,20,unfinished=>380,remaining_work=>'Printing',request_id=>retry);
 select id into lot from public.unfinished_lots where source_entry_id=entry;
 if lot is null or not exists(select 1 from public.unfinished_lots where id=lot and quantity_created=380 and quantity_available=380 and created_by=actor) then raise exception 'lot creation/traceability';end if;
 if not exists(select 1 from public.production_orders where id=item and good_quantity=600 and rejected_quantity=20 and produced_quantity=620 and remaining_quantity=400) then raise exception 'good-only/legacy meaning';end if;
 if public.record_production(f,'line',line1,item,tech,600,20,unfinished=>380,remaining_work=>'Printing',request_id=>retry)<>entry then raise exception 'idempotent creation';end if;
 partial:=public.record_production(f,'machine',machine,item,tech,180,10,unfinished=>10,remaining_work=>'Printing retry',input_lot=>lot,input_quantity=>200);
 select id into child from public.unfinished_lots where source_entry_id=partial;
 if not exists(select 1 from public.unfinished_lots where id=lot and quantity_available=180) or child is null then raise exception 'partial/reprocessing';end if;
 retry:=gen_random_uuid();
 perform public.record_production(f,'line',line2,item,tech,170,10,input_lot=>lot,input_quantity=>180,request_id=>retry);
 perform public.record_production(f,'line',line2,item,tech,170,10,input_lot=>lot,input_quantity=>180,request_id=>retry);
 if not exists(select 1 from public.unfinished_lots where id=lot and quantity_available=0) or (select count(*) from public.unfinished_operations where lot_id=lot)<>2 then raise exception 'full consumption/retry/operation assignment';end if;
 if (select jsonb_build_array(line_id,start_time,expected_finish,actual_start,status) from public.production_orders where id=item) is distinct from plan_before then raise exception 'WIP changed original execution/planning';end if;
 if not exists(select 1 from public.production_orders where id=item and good_quantity=950 and rejected_quantity=40 and remaining_quantity=50) then raise exception 'double counted';end if;
 perform public.correct_production_entry(f,entry,600,20,'Increase unfinished correction',unfinished=>400,remaining_work=>'Printing');
 if (select quantity_available from public.unfinished_lots where id=lot)<>20 then raise exception 'increase correction';end if;
 perform public.correct_production_entry(f,entry,600,20,'Decrease unfinished correction',unfinished=>390,remaining_work=>'Printing');
 if (select quantity_available from public.unfinished_lots where id=lot)<>10 then raise exception 'decrease correction';end if;
 -- Exact database failures, independently of UI hints.
 for stmt,expected in select * from (values
 (format('select public.record_production(%L,%L,%L,%L,%L,0,0,unfinished=>10)',f,'line',line1,item,tech),'unfinished_invalid'),
 (format('select public.record_production(%L,%L,%L,%L,%L,11,0,input_lot=>%L,input_quantity=>11)',f,'machine',machine,item,tech,lot),'unfinished_insufficient'),
 (format('select public.record_production(%L,%L,%L,%L,%L,5,0,input_lot=>%L,input_quantity=>10)',f,'machine',machine,item,tech,lot),'unfinished_conservation'),
 (format('select public.record_production(%L,%L,%L,%L,%L,10,0,input_lot=>%L,input_quantity=>10)',f,'machine',normal,item,tech,lot),'recording_invalid_unit'),
 (format('select public.record_production(%L,%L,%L,%L,%L,10,0,input_lot=>%L,input_quantity=>10)',f,'machine',machine,other_item,tech,lot),'unfinished_invalid_lot'),
 (format('select public.correct_production_entry(%L,%L,600,20,%L,unfinished=>370,remaining_work=>%L)',f,entry,'Invalid consumed correction','Printing'),'unfinished_already_consumed'),
 (format('select public.correct_production_entry(%L,%L,1,0,%L,unfinished=>0)',f,partial,'Invalid conservation correction'),'unfinished_conservation'),
 (format('select public.production_history(%L,%L::jsonb)',f,'{"good_op":"gte","good_min":"1"}'),'history_unit_required')) cases(statement,message)
 loop
 caught:=false;begin execute stmt;exception when others then if sqlerrm<>expected then raise exception 'expected %, got %',expected,sqlerrm;end if;caught:=true;end;
 if not caught then raise exception 'expected %',expected;end if;
 end loop;
 update public.work_center_capabilities set rate_unit='meter' where work_center_id=machine;
 caught:=false;begin perform public.record_production(f,'machine',machine,item,tech,10,0,input_lot=>lot,input_quantity=>10);exception when others then if sqlerrm<>'recording_invalid_unit' then raise;end if;caught:=true;end;
 if not caught then raise exception 'wrong capability unit accepted';end if;
 update public.work_center_capabilities set rate_unit='piece' where work_center_id=machine;
 delete from public.work_center_capabilities where work_center_id=machine;
 caught:=false;begin perform public.record_production(f,'machine',machine,item,tech,10,0,input_lot=>lot,input_quantity=>10);exception when others then if sqlerrm<>'recording_invalid_unit' then raise;end if;caught:=true;end;
 if not caught then raise exception 'missing capability accepted';end if;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,machine,product,100,'piece');
 update public.work_centers set archived=true where id=machine;
 caught:=false;begin perform public.record_production(f,'machine',machine,item,tech,10,0,input_lot=>lot,input_quantity=>10);exception when others then if sqlerrm<>'recording_invalid_unit' then raise;end if;caught:=true;end;
 if not caught then raise exception 'archived destination accepted';end if;
 update public.work_centers set archived=false where id=machine;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) select f,id,product2,100,'piece' from public.work_centers where line_id=line2;
 update public.production_orders set line_id=line2,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=other_item;
 perform public.start_product_item(f,other_item);
 caught:=false;begin perform public.record_production(f,'line',line2,item,tech,10,0,input_lot=>lot,input_quantity=>10);exception when others then if sqlerrm<>'recording_invalid_unit' then raise;end if;caught:=true;end;
 if not caught then raise exception 'unrelated active item on secondary line accepted';end if;
 perform public.finish_product_item(f,other_item);
 caught:=false;begin perform public.record_production(gen_random_uuid(),'machine',machine,item,tech,10,0,input_lot=>lot,input_quantity=>10);exception when others then if sqlerrm<>'permission_denied' then raise;end if;caught:=true;end;
 if not caught then raise exception 'cross-factory write accepted';end if;
 perform public.record_production(f,'machine',machine,item,tech,0.1,0.2,input_lot=>child,input_quantity=>0.3);
 if (select quantity_available from public.unfinished_lots where id=child)<>9.7 then raise exception 'exact fractional numeric conservation';end if;
 result:=public.production_history(f,jsonb_build_object('request',request,'measurement_unit','piece','unfinished_op','gte','unfinished_min','1'));
 if (result->>'total')::int<>2 or not exists(select 1 from jsonb_array_elements(result->'rows') e where (e->>'id')::uuid=entry and (e->>'scrap_percentage')::numeric=20*100/1010.0) then raise exception 'WIP history/physical percentage';end if;
 if jsonb_array_length(public.unfinished_inventory(f,true)->'rows')<2 then raise exception 'consumed lot hidden from audit';end if;
 only_wip:=public.record_production(f,'line',line1,item,tech,0,0,unfinished=>10,remaining_work=>'Printing only');
 if not exists(select 1 from public.production_entries where id=only_wip and produced=0 and effective_good=0 and effective_scrap=0 and effective_unfinished=10) then raise exception 'unfinished-only gross meaning';end if;
 correction_retry:=gen_random_uuid();
 perform public.correct_production_entry(f,only_wip,0,0,'WIP-only correction',request_id=>correction_retry,unfinished=>12,remaining_work=>'Printing only');
 perform public.correct_production_entry(f,only_wip,0,0,'WIP-only correction',request_id=>correction_retry,unfinished=>12,remaining_work=>'Printing only');
 if (select count(*) from public.production_entry_corrections where entry_id=only_wip)<>1 or (select quantity_available from public.unfinished_lots where source_entry_id=only_wip)<>12 then raise exception 'correction retry mutated stock twice';end if;
 for i in 1..55 loop perform public.record_production(f,'line',line1,item,tech,1,1,confirm_overproduction=>true);end loop;
 result:=public.production_history(f,jsonb_build_object('request',request,'product',product||','||product2,'measurement_unit','piece','good_op','eq','good_min','1','scrap_op','gte','scrap_min','50','scrap_metric','percentage','scrap_scope','shift'),'scrap','asc',2);
 if (result->>'total')::int<>55 or jsonb_array_length(result->'rows')<>5 or (result->'totals'->0->>'good')::numeric<>55 or (result->'shift_totals'->0->>'scrap_percentage')::numeric<>50 then raise exception 'server filtering beyond page1/full weighted totals';end if;
 result:=public.production_history(f,jsonb_build_object('request',request,'measurement_unit','piece','scrap_op','eq','scrap_min','50','scrap_metric','percentage','scrap_scope','row','technician',tech,'shift','unknown','corrected','no'));
 if (result->>'total')::int<>55 or jsonb_array_length(result->'rows')<>50 then raise exception 'combined category/row-percentage before pagination';end if;
 if before_history is distinct from (select jsonb_agg(to_jsonb(e) order by id) from public.production_entries e where factory_id=f and order_id<>item) then raise exception 'historical entries changed';end if;
 if before_centers is distinct from (select jsonb_agg(to_jsonb(c) order by id) from public.work_centers c where factory_id=f and coalesce(line_id,gen_random_uuid()) not in(line1,line2) and id<>machine) then raise exception 'physical/transfer assignments changed';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 caught:=false;begin perform public.unfinished_inventory(f);exception when others then if sqlerrm<>'permission_denied' then raise;end if;caught:=true;end;
 if not caught then raise exception 'permission bypass';end if;
 if has_table_privilege('authenticated','public.unfinished_lots','update') or has_table_privilege('authenticated','public.unfinished_movements','insert') or has_table_privilege('authenticated','public.unfinished_operations','insert') then raise exception 'direct ledger writes';end if;
end $test$;
rollback;
