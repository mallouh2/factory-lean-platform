-- TESTING only. All fixtures, schedule edits, entries and audit changes roll back.
begin;
create function pg_temp.shift_assert(ok boolean,message text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'shift test: %',message;end if;
end$$;
create function pg_temp.shift_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=expected then return;end if;raise;end;
 raise exception 'expected error %',expected;
end$$;
do $test$
declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';actor uuid:='d699a3ac-fab0-4faf-b958-f3902bc357ba';
 morning uuid;evening uuid;night uuid;foreign_factory uuid;foreign_shift uuid;
 product uuid;line uuid;request uuid;job public.production_orders;tech uuid;entry uuid;retry uuid:=gen_random_uuid();
 automatic uuid;manual uuid;before_entries jsonb;context jsonb;at_time timestamptz;
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select id into tech from public.memberships where factory_id=f and user_id=actor;
 select jsonb_agg(to_jsonb(e) order by id) into before_entries from public.production_entries e;
 update public.production_shifts set archived=true where factory_id=f and not archived;
 morning:=public.configure_production_shift(f,'QA Morning','صباح الاختبار','06:00','14:00');
 evening:=public.configure_production_shift(f,'QA Evening','مساء الاختبار','14:00','22:00');
 night:=public.configure_production_shift(f,'QA Night','ليل الاختبار','22:00','06:00');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-01 07:30+03')=morning,'daytime');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-01 14:00+03')=evening,'adjacent exclusive boundary');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-01 23:30+03')=night,'overnight before midnight');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-02 02:00+03')=night,'overnight after midnight');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-02 06:00+03')=morning,'overnight end excluded');
 perform pg_temp.shift_error(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Overlap','تداخل','13:00','21:00'),'shift_overlap');
 perform pg_temp.shift_error(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Overnight overlap','تداخل ليلي','05:00','13:00'),'shift_overlap');
 perform pg_temp.shift_error(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Equal','متساوية','06:00','06:00'),'shift_window_invalid');
 perform public.configure_production_shift(f,'QA Night','ليل الاختبار','22:00','06:00',night,true);
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-02 02:00+03') is null,'gap and archive');
 perform public.configure_production_shift(f,'QA Night','ليل الاختبار','22:00','06:00',night,false);
 -- UTC instant converted through the configured factory timezone, never the caller/session timezone.
 perform set_config('TimeZone','Pacific/Honolulu',true);
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-10-01 04:30Z')=morning,'factory timezone');
 update public.factories set timezone='America/New_York' where id=f;
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-03-08 10:30Z')=morning,'spring DST');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-11-01 11:30Z')=morning,'fall DST');
 perform pg_temp.shift_assert(private.resolve_factory_shift(f,'2026-11-01 05:30Z')=night and private.resolve_factory_shift(f,'2026-11-01 06:30Z')=night,'both repeated DST hours');
 update public.factories set timezone='Asia/Qatar' where id=f;
 perform set_config('TimeZone','UTC',true);
 insert into public.factories(name,created_by) values('QA shift isolation',actor) returning id into foreign_factory;
 insert into public.production_shifts(factory_id,name,name_ar,start_time,end_time,created_by) values(foreign_factory,'Foreign','أخرى','06:00','14:00',actor) returning id into foreign_shift;
 insert into public.products(factory_id,name,code,unit) values(f,'QA shift pipe','QS-'||substr(gen_random_uuid()::text,1,8),'meter') returning id into product;
 insert into public.production_lines(factory_id,name,code) values(f,'QA shift line','QS-'||substr(gen_random_uuid()::text,1,8)) returning id into line;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select f,'QA shift center','QS-'||substr(gen_random_uuid()::text,1,8),line,category_id from public.work_centers where factory_id=f and category_id is not null limit 1;
 request:=public.create_production_request(f,'QA shifts','normal',null,'QA internal production reason',jsonb_build_array(jsonb_build_object('product_id',product,'quantity',1000,'unit','meter')));
 update public.production_orders set line_id=line,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where request_id=request;
 perform public.start_product_item(f,(select id from public.production_orders where request_id=request));
 select * into job from public.production_orders where request_id=request;
 context:=public.production_shift_context(f);
 perform pg_temp.shift_assert((context->>'shift_id')::uuid=private.resolve_factory_shift(f,(context->>'timestamp')::timestamptz),'frontend context uses resolver');
 entry:=public.record_production(f,'line',line,job.id,tech,10,2,'QA automatic',false,retry);
 perform pg_temp.shift_assert(exists(select 1 from public.production_entries e where e.id=entry and e.shift_id=private.resolve_factory_shift(f,e.created_at)
 and e.shift_id=e.original_shift_id and e.shift_assignment_mode='automatic' and e.requested_shift_id is null),'server persisted exact timestamp attribution');
 select shift_id into automatic from public.production_entries where id=entry;
 manual:=case when automatic=morning then evening else morning end;
 perform pg_temp.shift_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L)',f,'line',line,job.id,tech,manual),'shift_override_reason');
 perform pg_temp.shift_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L,shift_override_reason=>%L)',f,'line',line,job.id,tech,foreign_shift,'Delayed entry'),'shift_invalid');
 perform public.record_production(f,'line',line,job.id,tech,1,0,shift=>manual,shift_override_reason=>'Delayed counter reading');
 perform pg_temp.shift_assert(exists(select 1 from public.production_entries e where e.order_id=job.id and e.shift_id=manual and e.automatic_shift_id=automatic
 and e.shift_override_reason='Delayed counter reading' and e.shift_override_by=actor and e.shift_override_at=e.created_at and e.shift_assignment_mode='manual'),'manual override audit');
 perform public.correct_production_entry(f,entry,10,2,'Correct shift identity',false,gen_random_uuid(),manual,true);
 perform pg_temp.shift_assert(exists(select 1 from public.production_entry_corrections where entry_id=entry and previous_shift_id=automatic and corrected_shift_id=manual and created_by=actor),'correction audit');
 -- Schedule edits are audited, future-only, and retries return the original entry despite a changed configuration.
 perform public.configure_production_shift(f,'QA Morning','صباح الاختبار','07:00','14:00',morning,false);
 perform pg_temp.shift_assert(exists(select 1 from public.audit_logs where entity='production_shifts' and entity_id=morning and actor_id=actor and old_data->>'start_time'='06:00:00' and new_data->>'start_time'='07:00:00'),'schedule audit');
 perform pg_temp.shift_assert(public.record_production(f,'line',line,job.id,tech,10,2,'QA automatic',false,retry)=entry,'retry does not resolve again');
 perform pg_temp.shift_assert((public.production_history(f,jsonb_build_object('request',request,'shift',manual))->>'total')::int=2,'history uses stored IDs after edits');
 update public.production_shifts set archived=true where factory_id=f;
 perform pg_temp.shift_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0,shift=>%L,shift_override_reason=>%L)',f,'line',line,job.id,tech,manual,'Delayed entry'),'shift_invalid');
 perform public.record_production(f,'line',line,job.id,tech,1,0,'QA unconfigured');
 perform pg_temp.shift_assert(exists(select 1 from public.production_entries where order_id=job.id and notes='QA unconfigured' and shift_id is null and shift_assignment_mode='unconfigured'),'no active shifts permits NULL');
 -- Create a tiny window away from the current factory-local time: submission rejects a gap.
 at_time:=clock_timestamp();
 perform public.configure_production_shift(f,'QA gap','فجوة الاختبار',((at_time at time zone 'Asia/Qatar')+interval '2 hours')::time,((at_time at time zone 'Asia/Qatar')+interval '3 hours')::time,morning,false);
 perform pg_temp.shift_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',line,job.id,tech),'shift_no_match');
 perform public.record_production(f,'line',line,job.id,tech,1,0,'QA gap manual',shift=>morning,shift_override_reason=>'Delayed production in gap');
 perform pg_temp.shift_assert(exists(select 1 from public.production_entries where order_id=job.id and notes='QA gap manual' and automatic_shift_id is null and shift_id=morning and shift_assignment_mode='manual'),'gap manual audit');
 perform pg_temp.shift_assert((select jsonb_agg(to_jsonb(e) order by id) from public.production_entries e where order_id<>job.id)=before_entries,'existing history including NULL untouched');
 perform pg_temp.shift_assert((select start_time=job.start_time and expected_finish=job.expected_finish and good_quantity=13 and rejected_quantity=2 from public.production_orders where id=job.id),'planning and quantity invariants');
 perform pg_temp.shift_assert(exists(select 1 from pg_constraint where conname='production_shift_no_overlap' and contype='x'),'concurrency exclusion constraint');
 perform pg_temp.shift_assert(not has_function_privilege('authenticated','private.record_production(uuid,text,uuid,uuid,uuid,numeric,numeric,text,boolean,uuid,uuid)','execute'),'old write path revoked');
 perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
 perform pg_temp.shift_error(format('select public.production_shift_context(%L)',f),'permission_denied');
 perform pg_temp.shift_error(format('select public.configure_production_shift(%L,%L,%L,%L,%L)',f,'Unauthorized','غير مصرح','06:00','14:00'),'permission_denied');
 perform pg_temp.shift_error(format('select public.record_production(%L,%L,%L,%L,%L,1,0)',f,'line',line,job.id,tech),'permission_denied');
end $test$;
rollback;
