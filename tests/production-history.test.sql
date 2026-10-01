-- TESTING-only integration: all shifts, declarations, audit and execution changes roll back.
begin;
create function pg_temp.expect_history_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=expected then return;end if;raise;end;
 raise exception 'expected failure %',expected;
end$$;
do $test$
declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a'; actor uuid:='d699a3ac-fab0-4faf-b958-f3902bc357ba';
 tech uuid;other_tech uuid;job public.production_orders;other_job public.production_orders;
 a uuid;b uuid;e uuid;retry uuid:=gen_random_uuid();result jsonb;filter jsonb;baseline bigint;i integer;
 qa_product uuid;qa_product2 uuid;qa_line uuid;qa_request uuid; foreign_factory uuid;foreign_shift uuid;
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 update public.production_shifts set archived=true where factory_id=f and not archived;
 select id into tech from public.memberships where factory_id=f and user_id=actor;
 select id into other_tech from public.memberships where factory_id=f and status='approved' and id<>tech limit 1;

 insert into public.products(factory_id,name,code,unit) values(f,'QA history pipe','QH-'||substr(gen_random_uuid()::text,1,8),'meter') returning id into qa_product;
 insert into public.products(factory_id,name,code,unit) values(f,'QA history fittings','QH-'||substr(gen_random_uuid()::text,1,8),'piece') returning id into qa_product2;
 insert into public.production_lines(factory_id,name,code) values(f,'QA history line','QH-'||substr(gen_random_uuid()::text,1,8)) returning id into qa_line;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'QA history center','QH-'||substr(gen_random_uuid()::text,1,8),qa_line,category_id from public.work_centers where factory_id=f and category_id is not null limit 1;
 qa_request:=public.create_production_request(f,'QA history request','normal',null,'',jsonb_build_array(jsonb_build_object('product_id',qa_product,'quantity',1000,'unit','meter'),jsonb_build_object('product_id',qa_product2,'quantity',1000,'unit','piece')));
 update public.production_orders set line_id=qa_line,start_time=now()-interval '2 hours',expected_finish=now()-interval '1 hour' where request_id=qa_request and product_id=qa_product;
 update public.production_orders set line_id=qa_line,start_time=now()-interval '1 hour',expected_finish=now() where request_id=qa_request and product_id=qa_product2;
 perform public.start_product_item(f,(select id from public.production_orders where request_id=qa_request and product_id=qa_product));
 select * into job from public.production_orders where request_id=qa_request and product_id=qa_product;


 a:=public.configure_production_shift(f,'QA Morning','صباح اختبار','06:00','14:00');
 b:=public.configure_production_shift(f,'QA Night','ليل اختبار','14:00','06:00');
 insert into public.factories(name,created_by) values('QA shift isolation',actor) returning id into foreign_factory;
 insert into public.production_shifts(factory_id,name,name_ar,created_by) values(foreign_factory,'Foreign shift','وردية أخرى',actor) returning id into foreign_shift;
 perform pg_temp.expect_history_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L)',f,'line',job.line_id,job.id,tech,foreign_shift),'shift_invalid');
 perform public.configure_production_shift(f,'QA Morning renamed','صباح معدّل','06:00','14:00',a,false);
 if (select name from public.production_shifts where id=a)<>'QA Morning renamed' then raise exception 'rename failed';end if;
 perform pg_temp.expect_history_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L)',f,'line',job.line_id,job.id,tech,gen_random_uuid()),'shift_invalid');
 e:=public.record_production(f,'line',job.line_id,job.id,tech,1,2,'QA history',false,retry,a,'QA delayed history entry');
 if public.record_production(f,'line',job.line_id,job.id,tech,1,2,'QA history',false,retry,a,'QA delayed history entry')<>e then raise exception 'shift retry changed identity';end if;
 perform pg_temp.expect_history_error(format('select public.record_production(%L,%L,%L,%L,%L,1,2,%L,false,%L,%L)',f,'line',job.line_id,job.id,tech,'QA history',retry,b),'request_conflict');
 for i in 2..65 loop
 perform public.record_production(f,'line',job.line_id,job.id,case when i%2=0 then tech else other_tech end,1,i%5,'QA history',false,gen_random_uuid(),case when i<=35 then a else b end,'QA delayed history entry');
 end loop;
 filter:=jsonb_build_object('request',job.request_id,'product',job.product_id,'unit','line:'||job.line_id,'from',to_char(current_timestamp at time zone (select timezone from public.factories where id=f),'YYYY-MM-DD'),'to',to_char(current_timestamp at time zone (select timezone from public.factories where id=f),'YYYY-MM-DD'));
 result:=public.production_history(f,filter,'scrap','desc',1);
 if (result->>'total')::int<>65 or jsonb_array_length(result->'rows')<>50 then raise exception 'filter/page failed: %',result;end if;
 if (result->'rows'->0->>'effective_scrap')::numeric<>4 then raise exception 'scrap descending failed';end if;
 if (result->'totals'->0->>'good')::numeric<>65 then raise exception 'summary covers only page';end if;
 if (result->'totals'->0->>'scrap')::numeric<>131 then raise exception 'scrap total failed';end if;
 if not exists(select 1 from jsonb_array_elements(result->'highest') x where x->>'kind'='unit' and x->>'identity'='line:'||job.line_id and (x->>'scrap')::numeric=131) then raise exception 'highest unit failed';end if;
 if not exists(select 1 from jsonb_array_elements(result->'highest') x where x->>'kind'='shift' and x->>'identity'=a::text) then raise exception 'highest shift failed';end if;
 result:=public.production_history(f,filter,'scrap','desc',2);
 if jsonb_array_length(result->'rows')<>15 or (result->'totals'->0->>'good')::numeric<>65 then raise exception 'page2 summary/filter failed';end if;
 if (public.production_history(f,filter||jsonb_build_object('shift',a))->>'total')::int<>35 then raise exception 'shift filter failed';end if;
 if (public.production_history(f,filter||jsonb_build_object('technician',tech))->>'total')::int<>33 then raise exception 'technician filter failed';end if;
 if (public.production_history(f,filter||jsonb_build_object('shift',a,'technician',tech))->>'total')::int<>18 then raise exception 'combined filter failed';end if;
 if (public.production_history(f,filter||'{"from":"1990-01-01","to":"1990-01-02"}')->>'total')::int<>0 then raise exception 'date exclusion failed';end if;
 perform public.correct_production_entry(f,e,2,3,'QA shift correction',false,gen_random_uuid(),b,true);
 if not exists(select 1 from public.production_entry_corrections where entry_id=e and previous_shift_id=a and corrected_shift_id=b and shift_changed and created_by=actor) then raise exception 'shift correction audit missing';end if;
 if not exists(select 1 from public.production_entries where id=e and shift_id=b and original_shift_id=a and good_quantity=1 and effective_good=2) then raise exception 'original shift/output lost';end if;
 if (public.production_history(f,filter||'{"corrected":"yes"}')->>'total')::int<>1 then raise exception 'corrected filter failed';end if;
 if (public.production_history(f,filter,'good','desc')->'rows'->0->>'effective_good')::numeric<>2 then raise exception 'good sort failed';end if;
 perform public.configure_production_shift(f,'QA Night','ليل اختبار','14:00','06:00',b,true);
 perform pg_temp.expect_history_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L)',f,'line',job.line_id,job.id,tech,b),'shift_invalid');
 if (public.production_history(f,filter||jsonb_build_object('shift',b))->>'total')::int<>31 then raise exception 'archived historical shift lost';end if;
 perform public.configure_production_shift(f,'QA Night','ليل اختبار','14:00','06:00',b,false);
 if (select archived from public.production_shifts where id=b) then raise exception 'reactivation failed';end if;
 -- Parent request audit includes declarations from another Product Item/unit.
 select * into other_job from public.production_orders where factory_id=f and request_id=job.request_id and status='planned' and line_id=job.line_id order by start_time,id limit 1;
 if other_job.id is null then raise exception 'same request next planned item required';end if;
 perform public.finish_product_item(f,job.id);perform public.start_product_item(f,other_job.id);
 perform public.record_production(f,'line',other_job.line_id,other_job.id,tech,10,1,'QA second item',false,gen_random_uuid(),a,'QA delayed history entry');
 result:=public.production_history(f,jsonb_build_object('request',job.request_id,'from',filter->>'from','to',filter->>'to'));
 if (result->>'total')::int<>66 then raise exception 'request omitted other Product Item';end if;
 if jsonb_array_length(result->'totals')<>2 then raise exception 'units combined';end if;
 -- Each sort is supported; chronological ordering remains deterministic with ties.
 perform public.production_history(f,filter,'date','asc');perform public.production_history(f,filter,'unit','asc');
 perform public.production_history(f,filter,'technician','desc');perform public.production_history(f,filter,'shift','asc');
 if exists(select 1 from jsonb_array_elements(public.production_history(f,'{"shift":"unknown"}')->'rows') x where x->>'shift_id' is not null) then raise exception 'unknown shift fabricated';end if;
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 perform pg_temp.expect_history_error(format('select public.production_history(%L)',f),'permission_denied');
 perform pg_temp.expect_history_error(format('select public.production_history_options(%L)',f),'permission_denied');
 perform pg_temp.expect_history_error(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Unauthorized','غير مصرح','06:00','14:00'),'permission_denied');
 perform set_config('request.jwt.claim.sub',actor::text,true);
 perform pg_temp.expect_history_error(format('select public.production_history(%L)',gen_random_uuid()),'permission_denied');
 perform pg_temp.expect_history_error(format('select public.production_history(%L)',foreign_factory),'permission_denied');
 if has_table_privilege('authenticated','public.production_shifts','delete') then raise exception 'shift hard delete exposed';end if;
 if has_function_privilege('authenticated','private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid)','execute') then raise exception 'shift validation bypass exposed';end if;
end $test$;
rollback;
