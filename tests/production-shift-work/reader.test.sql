create table shift_test.context(x jsonb);
create function shift_test.new_job(x jsonb,slot integer,l uuid default null,finish boolean default true) returns uuid language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;r uuid;i uuid;begin
 r:=public.create_production_request(f,'M1 local job '||slot,'normal',null,'Disposable reader acceptance',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',100,'unit','meter')));
 select id into i from public.production_orders where request_id=r;
 perform public.plan_product_item(f,i,coalesce(l,(x->>'line')::uuid),date_trunc('day',clock_timestamp())+interval '2 days 1 hour'+slot*interval '2 minutes');
 perform public.start_product_item(f,i);
 if finish then perform public.finish_product_item(f,i);end if;
 return i;
end$$;
do $$declare x jsonb;f uuid;s timestamptz;shift uuid;i uuid;j uuid;member uuid;page jsonb;occ jsonb;job public.production_orders;e jsonb;
 c jsonb;seen uuid[]:='{}';value jsonb;n integer:=0;first_id uuid;last_id uuid;foreign_f uuid;pkg uuid;before_digest text;retry uuid:=gen_random_uuid();entry_id uuid;payload jsonb;begin
 x:=mp_test.fixture('reader');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'Reader acceptance','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 perform public.configure_center_capabilities(f,(x->>'other_machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 s:=clock_timestamp()+interval '.3 seconds';
 shift:=public.configure_production_shift(f,'Current acceptance','وردية الاختبار',s::time,(s+interval '4 hours')::time);
 perform shift_test.ok(public.production_shift_work(f)->>'reason'='OCCURRENCE_NOT_READY','reader unavailable before first full shift');
 perform pg_sleep(.4);
 for n in 1..251 loop i:=shift_test.new_job(x,n);if n=1 then first_id:=i;end if;end loop;
 i:=shift_test.new_job(x,252,null,false);j:=shift_test.new_job(x,253,(x->>'other_line')::uuid,false);
 x:=x||jsonb_build_object('active',i,'active_other',j,'completed',first_id,'shift',shift);
 insert into shift_test.context values(x);
 page:=public.production_shift_work(f);occ:=page->'occurrence';
 perform shift_test.ok(page->>'total'='253' and jsonb_array_length(page->'rows')=50 and not (page->>'complete')::boolean,'253 actual jobs exceed one bounded page');
 perform shift_test.ok(page#>>'{rows,0,status}'='active' and page#>>'{rows,1,status}'='active','active first on two distinct capable lines');
 perform shift_test.ok(not exists(select 1 from public.production_entries where factory_id=f),'zero-entry jobs included without inference from quantities');
 perform shift_test.ok((select count(distinct v->>'execution_key')=50 from jsonb_array_elements(page->'rows') v),'same product keeps distinct execution keys');
 perform shift_test.ok(page#>>'{rows,0,remaining_quantity}'='100' and page#>>'{rows,0,unit}'='meter','authoritative remaining and unit');
 n:=0;c:=null;
 loop
  page:=public.production_shift_work(f,c,50);n:=n+1;
  for value in select * from jsonb_array_elements(page->'rows') loop
   perform shift_test.ok(not (value->>'item_id')::uuid=any(seen),'unique keyset row '||(value->>'item_id'));
   seen:=array_append(seen,(value->>'item_id')::uuid);
  end loop;
  exit when (page->>'complete')::boolean;c:=page->'next_cursor';
 end loop;
 perform shift_test.ok(cardinality(seen)=253 and n=6 and page->'next_cursor'='null','complete deterministic traversal with no silent cap');
 page:=public.production_shift_work(f,null,100);
 perform shift_test.ok(jsonb_array_length(page->'rows')=100,'maximum bounded page');
 perform shift_test.fails(format('select public.production_shift_work(%L,null,101)',f),'22023');
 c:=page->'next_cursor';
 perform shift_test.fails(format('select public.production_shift_work(%L,%L,100)',f,c-'as_of'),'22023');
 perform shift_test.fails(format('select public.production_shift_work(%L,%L,100)',f,c||'{"extra":1}'),'22023');
 -- Real stock posting and retry remain on the original active path.
 select id into member from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 payload:=jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',i,'technician',member,'good',2,'discarded_quantity',0,'scrap_kg',0,'unfinished',0,'input_quantity',0);
 entry_id:=(public.record_lean_production(f,payload,retry)->>'id')::uuid;
 perform shift_test.ok((public.record_lean_production(f,payload,retry)->>'id')::uuid=entry_id,'ordinary active recording retry idempotent');
 perform shift_test.ok((select on_hand=2 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid and unit='meter'),'active Good credits inventory once');
 perform shift_test.fails(format('select public.production_shift_work(%L,%L,100)',f,c),'40001');
 page:=public.production_shift_work(f);c:=page->'next_cursor';
 update public.products set name='Renamed product' where factory_id=f and id=(x->>'product')::uuid;
 perform shift_test.fails(format('select public.production_shift_work(%L,%L)',f,c),'40001');
 page:=public.production_shift_work(f);c:=page->'next_cursor';
 perform public.finish_product_item(f,j);
 perform shift_test.fails(format('select public.production_shift_work(%L,%L)',f,c),'40001');
 payload:=payload||jsonb_build_object('item',first_id);
 before_digest:=shift_test.digest(f);
 perform shift_test.fails(format('select public.record_lean_production(%L,%L,gen_random_uuid())',f,payload),'recording_invalid_unit');
 perform shift_test.ok(shift_test.digest(f)=before_digest,'completed ordinary writes rejected without inventory effects');
 page:=public.production_shift_work(f);c:=page->'next_cursor';
 perform public.configure_production_shift(f,'Pending rename','تعديل مستقبلي',s::time,(s+interval '4 hours')::time,shift);
 perform shift_test.fails(format('select public.production_shift_work(%L,%L)',f,c),'40001');
 perform shift_test.ok(public.production_shift_work(f)->'occurrence'=occ,'future configuration preserves current reader occurrence');
 select * into job from public.production_orders where id=i;
 e:=private.production_recording_eligibility(job,occ,clock_timestamp());
 perform shift_test.ok((e->>'included')::boolean and not (e->>'late_recording_available')::boolean,'shared eligibility active and late capability disabled');
 job.actual_start:=(occ->>'starts_at')::timestamptz;job.status:='active';job.actual_finish:=null;
 perform shift_test.ok((private.production_recording_eligibility(job,occ,clock_timestamp())->>'included')::boolean,'execution at occurrence start');
 job.actual_start:=(occ->>'ends_at')::timestamptz;
 perform shift_test.ok(not (private.production_recording_eligibility(job,occ,clock_timestamp())->>'included')::boolean,'execution at occurrence end excluded');
 select * into job from public.production_orders where id=i;
 perform shift_test.ok((private.production_recording_eligibility(job,occ||jsonb_build_object('starts_at',clock_timestamp()+interval '1 second','ends_at',clock_timestamp()+interval '1 hour'),clock_timestamp()+interval '2 seconds')->>'included')::boolean,'ongoing execution spanning prior shift');
 job.actual_start:=(occ->>'starts_at')::timestamptz-interval '1 day';
 job.status:='completed';job.actual_finish:=(occ->>'starts_at')::timestamptz;
 perform shift_test.ok(private.production_recording_eligibility(job,occ,clock_timestamp())->>'blocked_reason'='OUTSIDE_CURRENT_SHIFT','finish at shift start excluded');
 job.actual_start:=(occ->>'starts_at')::timestamptz;job.actual_finish:=job.actual_start;
 perform shift_test.ok(private.production_recording_eligibility(job,occ,clock_timestamp())->>'blocked_reason'='EXECUTION_STATE_INVALID','zero-duration execution rejected');
 job.actual_start:=null;
 perform shift_test.ok(private.production_recording_eligibility(job,occ,clock_timestamp())->>'blocked_reason'='ACTUAL_START_MISSING','missing execution start rejected');
 select * into job from public.production_orders where id=i;job.line_id:=(x->>'other_line')::uuid;
 perform shift_test.ok(private.production_recording_eligibility(job,occ,clock_timestamp())->>'blocked_reason'='EXECUTED_LINE_UNVERIFIED','historical line mismatch rejected');
 select * into job from public.production_orders where id=i;job.planning_ever_scheduled:=false;
 perform shift_test.ok(private.production_recording_eligibility(job,occ,clock_timestamp())->>'blocked_reason'='EXECUTED_LINE_UNVERIFIED','unsupported legacy execution excluded');
 job.line_id:=null;
 perform shift_test.ok(not (private.production_recording_eligibility(job,occ,clock_timestamp())->>'included')::boolean,'independent history excluded without breaking existing workflow');
 perform shift_test.ok(not exists(select 1 from jsonb_array_elements(public.production_shift_work(f)->'rows') v where v->>'item_id'=x->>'item'),'planned never started excluded');

 -- Direct and package permissions tested with the actual authenticated SQL role.
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,(x->>'viewer')::uuid,'orders','view');
 perform set_config('request.jwt.claim.sub',x->>'viewer',true);execute 'set local role authenticated';
 page:=public.production_shift_work(f);
 perform shift_test.ok((page->>'total')::integer=253 and not (page->>'can_edit')::boolean and not exists(select 1 from jsonb_array_elements(page->'rows') v where (v->>'can_record')::boolean),'view-only direct permission reads without recording capability');
 execute 'reset role';
 delete from public.user_permissions where factory_id=f and user_id=(x->>'viewer')::uuid and module='orders';
 execute 'set local role authenticated';
 perform shift_test.fails(format('select public.production_shift_work(%L)',f),'42501');execute 'reset role';
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 select id into pkg from public.permission_packages where factory_id=f and template_key='planning_engineer';
 perform public.set_member_permission_packages(f,(x->>'worker')::uuid,array[pkg],array[]::uuid[]);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);execute 'set local role authenticated';
 perform shift_test.ok((public.production_shift_work(f)->>'total')::integer=253,'package grant authorizes reader');execute 'reset role';
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform public.set_member_permission_packages(f,(x->>'worker')::uuid,array[]::uuid[],array[pkg]);
 perform set_config('request.jwt.claim.sub',x->>'worker',true);execute 'set local role authenticated';
 perform shift_test.fails(format('select public.production_shift_work(%L)',f),'42501');execute 'reset role';
 select (b.x->>'factory')::uuid into foreign_f from shift_test.baseline b;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);execute 'set local role authenticated';
 perform shift_test.fails(format('select public.production_shift_work(%L)',foreign_f),'42501');
 perform shift_test.fails('select * from private.production_shift_schedule_revisions','42501');
 execute 'reset role';
 perform shift_test.ok(not has_function_privilege('anon','public.production_shift_work(uuid,jsonb,integer)','execute'),'anonymous reader denied');
 perform shift_test.ok(not has_function_privilege('authenticated','private.materialize_production_occurrence(uuid,jsonb)','execute'),'private materialization denied');
 perform shift_test.ok(not has_function_privilege('authenticated','private.configure_shift_before_occurrences(uuid,text,text,time,time,uuid,boolean)','execute'),'configuration wrapper cannot be bypassed');
 perform shift_test.ok((select bool_and(prosecdef and proconfig @> array['search_path=""']) from pg_proc where oid in ('public.production_shift_work(uuid,jsonb,integer)'::regprocedure)),'definer reader has empty search path');
end$$;

-- A real read-only transaction rejects any accidental writer deep in the call graph.
begin read only;
do $$declare x jsonb;before text;occ_count bigint;page jsonb;begin
 select c.x into x from shift_test.context c;
 before:=shift_test.digest((x->>'factory')::uuid);select count(*) into occ_count from private.production_shift_occurrences;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);execute 'set local role authenticated';
 page:=public.production_shift_work((x->>'factory')::uuid);execute 'reset role';
 if page->>'total'<>'253' or shift_test.digest((x->>'factory')::uuid) is distinct from before or (select count(*) from private.production_shift_occurrences)<>occ_count then raise exception 'Reader side effects';end if;
end$$;
commit;
select shift_test.ok(true,'authenticated read-only transaction preserves inventory, WIP, machines, Maintenance and occurrences');
-- Measured, factory-scoped representative workload and actual candidate/keyset plans.
analyze public.production_orders;
select set_config('request.jwt.claim.sub',(select x->>'owner' from shift_test.context),false);
explain (analyze,buffers) select public.production_shift_work((select (x->>'factory')::uuid from shift_test.context));
explain (analyze,buffers) select o.id from public.production_orders o where o.factory_id=(select (x->>'factory')::uuid from shift_test.context)
 and status in ('active','completed') and actual_start<=clock_timestamp() and (actual_finish is null or actual_finish>clock_timestamp()-interval '4 hours')
 order by case when status='active' then 0 else 1 end,actual_start desc,id limit 51;
explain (analyze,buffers) with context as materialized (
 select public.production_shift_work((select (x->>'factory')::uuid from shift_test.context)) p
) select o.id from public.production_orders o cross join context c
 where o.factory_id=(c.p->>'factory_id')::uuid and o.status in ('active','completed')
 and o.actual_start<=(c.p->>'evaluation_as_of')::timestamptz
 and o.actual_start<(c.p#>>'{occurrence,ends_at}')::timestamptz
 and (o.actual_finish is null or o.actual_finish>(c.p#>>'{occurrence,starts_at}')::timestamptz)
 and (case when o.status='active' then 0 else 1 end,-extract(epoch from o.actual_start),o.id)>
 ((c.p#>>'{next_cursor,last_state}')::integer,-extract(epoch from (c.p#>>'{next_cursor,last_start}')::timestamptz),(c.p#>>'{next_cursor,last_id}')::uuid)
 and (private.production_recording_eligibility(o,c.p->'occurrence',(c.p->>'evaluation_as_of')::timestamptz)->>'included')::boolean
 order by case when o.status='active' then 0 else 1 end,o.actual_start desc,o.id limit 51;
select count(*)||' reader assertions passed' from shift_test.assertions;
