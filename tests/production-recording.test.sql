-- TESTING only; existing items and every temporary entry/assignment/audit roll back.
begin;
create function pg_temp.expect_recording_error(statement text,expected text)
returns void language plpgsql as $$begin
 begin execute statement;
 exception when others then if sqlerrm=expected then return;end if;raise exception 'expected %, got %',expected,sqlerrm;end;
 raise exception 'expected % but command succeeded',expected;
end$$;
do $test$
declare f uuid;actor uuid;tech uuid;tech2 uuid;job public.production_orders;other_job public.production_orders;
 e uuid;r uuid:=gen_random_uuid();independent uuid;normal uuid;before_other numeric;before_machine jsonb;
 original_count integer;finished timestamptz;
 qa_product uuid;qa_product2 uuid;qa_line uuid;qa_request uuid;
begin
 select m.factory_id,m.user_id,m.id into f,actor,tech from public.memberships m
 join public.factories fac on fac.id=m.factory_id where fac.is_demo and m.status='approved'
 and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id and p.user_id=m.user_id and p.module='orders' and p.action='edit')
 and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id and p.user_id=m.user_id and p.module='orders' and p.action='view') limit 1;
 if f is null then raise exception 'approved TESTING person required';end if;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 -- Isolate quantity/execution tests from the factory's current shift configuration; rolled back.
 update public.production_shifts set archived=true where factory_id=f and not archived;

 insert into public.products(factory_id,name,code,unit) values(f,'QA history pipe','QH-'||substr(gen_random_uuid()::text,1,8),'meter') returning id into qa_product;
 insert into public.products(factory_id,name,code,unit) values(f,'QA history fittings','QH-'||substr(gen_random_uuid()::text,1,8),'piece') returning id into qa_product2;
 insert into public.production_lines(factory_id,name,code) values(f,'QA history line','QH-'||substr(gen_random_uuid()::text,1,8)) returning id into qa_line;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'QA history center','QH-'||substr(gen_random_uuid()::text,1,8),qa_line,category_id from public.work_centers where factory_id=f and category_id is not null limit 1;
 qa_request:=public.create_production_request(f,'QA history request','normal',null,'QA internal production reason',jsonb_build_array(jsonb_build_object('product_id',qa_product,'quantity',1000,'unit','meter'),jsonb_build_object('product_id',qa_product2,'quantity',1000,'unit','piece')));
 update public.production_orders set line_id=qa_line,start_time=now()-interval '2 hours',expected_finish=now()-interval '1 hour' where request_id=qa_request and product_id=qa_product;
 update public.production_orders set line_id=qa_line,start_time=now()-interval '1 hour',expected_finish=now() where request_id=qa_request and product_id=qa_product2;
 perform public.start_product_item(f,(select id from public.production_orders where request_id=qa_request and product_id=qa_product));
 select * into job from public.production_orders where request_id=qa_request and product_id=qa_product;


 select * into other_job from public.production_orders where factory_id=f and status='active' and actual_start is not null and id<>job.id limit 1;
 before_other:=other_job.good_quantity;
 select id into tech2 from public.memberships where factory_id=f and status='approved' and id<>tech limit 1;
 tech2:=coalesce(tech2,tech);
 select id into normal from public.work_centers where factory_id=f and line_id=job.line_id and not archived limit 1;
 select jsonb_agg(to_jsonb(x) order by id) into before_machine from public.work_centers x where factory_id=f;
 e:=public.record_production(f,'line',job.line_id,job.id,tech,300,10,'Shift 1',false,r);
 if public.record_production(f,'line',job.line_id,job.id,tech,300,10,'Shift 1',false,r)<>e then raise exception 'retry changed ID';end if;
 if (select good_quantity from public.production_orders where id=job.id)<>300 then raise exception 'first shift/idempotency failed';end if;
 perform public.record_production(f,'line',job.line_id,job.id,tech2,250,20,'Shift 2');
 if (select remaining_quantity from public.production_orders where id=job.id)<>450 then raise exception 'second shift mixed scrap into demand';end if;
 perform public.record_production(f,'line',job.line_id,job.id,tech,100,20,'Shift 3');
 if (select good_quantity from public.production_orders where id=job.id)<>650 then raise exception 'scrap counted as good';end if;
 if (select good_quantity from public.production_orders where id=other_job.id)<>before_other then raise exception 'cross-item totals changed';end if;
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'machine',normal,job.id,tech),'recording_invalid_unit');
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',other_job.line_id,job.id,tech),'recording_invalid_unit');
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',gen_random_uuid(),job.id,tech),'recording_invalid_unit');
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',job.line_id,job.id,gen_random_uuid()),'invalid_operator');
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,400,0)',f,'line',job.line_id,job.id,tech),'recording_overproduction_confirmation');
 perform public.correct_production_entry(f,e,280,15,'Shift counter corrected');
 if (select good_quantity from public.production_orders where id=job.id)<>630 then raise exception 'correction aggregate failed';end if;
 if (select good_quantity from public.production_entries where id=e)<>300 or (select scrap_quantity from public.production_entries where id=e)<>10 then raise exception 'original entry destroyed';end if;
 if not exists(select 1 from public.production_entry_corrections where entry_id=e and previous_good=300 and corrected_good=280 and created_by=actor) then raise exception 'correction audit missing';end if;
 perform public.record_production(f,'line',job.line_id,job.id,tech,400,0,'Confirmed extra output',true);
 if not exists(select 1 from public.production_orders where id=job.id and good_quantity=1030 and remaining_quantity=0 and overproduction_quantity=30 and status='active' and actual_finish is null and start_time=job.start_time and expected_finish=job.expected_finish and actual_start=job.actual_start) then raise exception 'overproduction/lifecycle/planning failed';end if;
 -- Independent explicit active assignment uses the existing resolver and a typed capability.
 insert into public.work_centers(factory_id,name,code,type,category_id,dependency_mode,line_id,order_id)
 select f,'Recording QA independent','RECORD-'||substr(gen_random_uuid()::text,1,8),type,category_id,'independent',null,other_job.id
 from public.work_centers where id=normal returning id into independent;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
 values(f,independent,other_job.product_id,100,case when other_job.unit='meter' then 'piece' else 'meter' end);
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'machine',independent,other_job.id,tech),'recording_invalid_unit');
 update public.work_center_capabilities set rate_unit=other_job.unit where work_center_id=independent;
 perform public.record_production(f,'machine',independent,other_job.id,tech,5,20);
 if (select good_quantity from public.production_orders where id=other_job.id)<>before_other+5 then raise exception 'independent output failed';end if;
 if before_machine is distinct from (select jsonb_agg(to_jsonb(x) order by id) from public.work_centers x where factory_id=f and id<>independent) then raise exception 'recording changed physical/assignment state';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',job.line_id,job.id,tech),'permission_denied');
 perform pg_temp.expect_recording_error(format('select public.correct_production_entry(%L,%L,1,0,%L)',f,e,'unauthorized change'),'permission_denied');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform public.finish_product_item(f,job.id);
 perform pg_temp.expect_recording_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',job.line_id,job.id,tech),'recording_invalid_unit');
 if has_function_privilege('authenticated','public.record_output(uuid,uuid,uuid,numeric,numeric,text,uuid)','execute') then raise exception 'legacy machine writer still exposed';end if;
 if has_table_privilege('authenticated','public.production_entries','update') or has_table_privilege('authenticated','public.production_entry_corrections','insert') then raise exception 'ledger can be silently edited';end if;
end $test$;
rollback;
