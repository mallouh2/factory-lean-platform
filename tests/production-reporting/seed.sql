-- Local operational fixtures use the unchanged protected M2 and Lean commands.
create schema reporting_test;
create table reporting_test.checks(label text);
create table reporting_test.context(x jsonb);
create function reporting_test.ok(v boolean,label text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL %',label;end if;insert into reporting_test.checks values(label);end$$;
create function reporting_test.fails(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if sqlstate=expected or sqlerrm=expected then insert into reporting_test.checks values('denied '||expected);return;else raise;end if;end;
 raise exception 'Expected %',expected;end$$;
create function reporting_test.digest() returns text language plpgsql stable as $$
declare tab text;part text;result text:='';begin
 foreach tab in array array['production_orders','production_entries','production_entry_corrections','finished_goods_balances','finished_goods_sources','finished_goods_movements','finished_goods_entry_receipts','finished_goods_reservations','finished_goods_source_reservations','sales_incoming_allocations','quality_rejections','quality_notifications','unfinished_lots','unfinished_movements','lean_scrap_events','lean_saved_comparisons','production_loss_estimates','downtime_events','production_transfers','maintenance_schedules','audit_logs'] loop
  execute format('select md5(coalesce(string_agg(x::text,''|'' order by x::text),'''')) from (select to_jsonb(t) x from public.%I t)s',tab) into part;
  result:=result||tab||part;
 end loop;
 foreach tab in array array['production_shift_occurrences','production_shift_schedule_revisions','production_recording_v3_activation'] loop
  execute format('select md5(coalesce(string_agg(x::text,''|'' order by x::text),'''')) from (select to_jsonb(t) x from private.%I t)s',tab) into part;result:=result||tab||part;
 end loop;return md5(result);end$$;
do $$declare x jsonb;f uuid;c uuid:=gen_random_uuid();a uuid;b uuid;problem uuid;event uuid;begin
 select t.x into x from late_test.context t;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 perform public.lean_command(f,gen_random_uuid(),'cause',jsonb_build_object('id',c,'name','Local reporting cause','name_ar','سبب الاختبار'));
 select id into a from public.production_entries where factory_id=f and effective_scrap_kg>0 order by created_at limit 1;
 select id into b from public.production_entries where factory_id=f and effective_scrap_kg>0 and id<>a order by created_at limit 1;
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',jsonb_build_object('id',gen_random_uuid(),'entry_id',a,'occurred_at',clock_timestamp(),'preliminary_cause_id',c,'observation','Unreviewed local Scrap','response','Recorded for review'));
 event:=gen_random_uuid();
 perform public.lean_command(f,gen_random_uuid(),'scrap_observation',jsonb_build_object('id',event,'entry_id',b,'occurred_at',clock_timestamp(),'preliminary_cause_id',c,'observation','Reviewed local Scrap','response','Controlled fixture response'));
 perform public.lean_command(f,gen_random_uuid(),'scrap_review',jsonb_build_object('id',event,'approved_cause_id',c,'note','Independent local review fixture','expected_revision',1));
 problem:=(public.lean_command(f,gen_random_uuid(),'problem',jsonb_build_object('mechanism','scrap','line_id',x->>'line','product_id',x->>'product','cause_id',c,'expected_revision',0)))->>'id';
 insert into public.lean_saved_comparisons(id,factory_id,problem_id,product_id,cutoff,desired_hours,evidence,created_by)
 values(gen_random_uuid(),f,problem,(x->>'product')::uuid,clock_timestamp(),1,'{"version":1,"fixture":"immutable baseline","time_basis":"recorded"}',(x->>'owner')::uuid);
 -- A populated immutable Loss fixture; no model is calculated by this task.
 insert into public.downtime_events(factory_id,work_center_id,reason_id,started_at,ended_at,created_by)
 values(f,(x->>'machine')::uuid,c,clock_timestamp()-interval '2 minutes',clock_timestamp()-interval '1 minute',(x->>'owner')::uuid) returning id into event;
 insert into public.production_loss_estimates(factory_id,event_id,model_version,result,recorded_by)
 values(f,event,1,'{"model_version":1,"fixture":"saved reviewed evidence"}',(x->>'owner')::uuid);
 insert into reporting_test.context values(x||jsonb_build_object('unreviewed',a,'reviewed',b,'cause',c));
end$$;
create table reporting_test.saved as select 'lean' kind,id,to_jsonb(s) snapshot from public.lean_saved_comparisons s
 union all select 'loss',id,to_jsonb(s) from public.production_loss_estimates s;
