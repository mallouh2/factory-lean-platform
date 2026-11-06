do $$declare x jsonb;f uuid;s timestamptz;sid uuid;page jsonb;p jsonb;r jsonb;job public.production_orders;begin
 x:=mp_test.fixture('same-shift-qatar');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'Local same-shift timezone','Asia/Qatar',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 s:=clock_timestamp()+interval '.2 seconds';sid:=public.configure_production_shift(f,'Qatar shift','وردية قطر',(s at time zone 'Asia/Qatar')::time,((s+interval '1 hour')at time zone 'Asia/Qatar')::time);perform pg_sleep(.3);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 day');perform public.start_product_item(f,(x->>'item')::uuid);perform pg_sleep(.01);perform public.finish_product_item(f,(x->>'item')::uuid);
 page:=public.production_shift_work(f);p:=same_shift_test.payload(x,1);r:=public.record_manufactured_output(f,p,gen_random_uuid());
 perform same_shift_test.ok(page#>>'{occurrence,timezone}'='Asia/Qatar' and page#>>'{occurrence,business_date}'=(clock_timestamp()at time zone 'Asia/Qatar')::date::text,'factory-local date/timezone is authoritative');
 perform same_shift_test.ok((select shift_id=sid and original_period_end=execution_finished_at and created_at<accepted_at from public.production_entries where id=(r->>'entry_id')::uuid),'timezone-aware recording preserves exact shift and execution interval');
 select * into job from public.production_orders where id=(x->>'item')::uuid;
 perform same_shift_test.ok(private.production_recording_eligibility(job,page->'occurrence',(page#>>'{occurrence,ends_at}')::timestamptz)->>'included'='false','half-open occurrence excludes its exact end boundary');
end$$;
select count(*) as same_shift_assertions from same_shift_test.checks;
