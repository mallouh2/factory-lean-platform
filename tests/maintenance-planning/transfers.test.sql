begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'MP transfer assertion failed: %',label;end if;insert into assertions values(label);
end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;
end$$;
do $$declare x jsonb;f uuid;r uuid;sid uuid;t uuid;reason uuid;start_at timestamptz;begin
 x:=mp_test.fixture('transfer');f:=(x->>'factory')::uuid;
 update private.maintenance_planning_activation set enabled=true;
 perform public.configure_center_capabilities(f,(x->>'independent')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',100,'rate_unit','meter','setup_minutes',5)));
 perform public.configure_center_alternatives(f,(x->>'machine')::uuid,array[(x->>'independent')::uuid]);
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'independent','title','Reserved alternative','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'assigned_to',x->>'worker'),gen_random_uuid());
 start_at:=clock_timestamp()+interval '1 day';sid:=mp_test.plan(x||jsonb_build_object('request',r),start_at);
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''confirm'',%L,1,gen_random_uuid())',f,r,jsonb_build_object('alternative',x->>'other_machine')),'maintenance_invalid');
 -- Explicit independent routing and a known non-overlapping plan establish the reader's required evidence.
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,1,'work_center',(x->>'independent')::uuid);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,start_at+interval '1 hour');
 perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
 perform public.start_product_item(f,(x->>'item')::uuid);
 perform public.stop_machine(f,(x->>'machine')::uuid,'planned',null,'preventive_maintenance','Explicit isolated physical stop');
 perform pg_temp.fails(format('select public.transfer_production(%L,%L,%L,''No future release assumption'')',f,x->>'machine',x->>'independent'),'maintenance_capacity_reserved');
 perform pg_temp.ok((select count(*)=0 from public.production_transfers where factory_id=f),'failed transfer creates no OPEN ownership');
 perform mp_test.command(f,r,'unschedule','{"reason":"Remove future alternative reservation"}',2,gen_random_uuid());
 t:=public.transfer_production(f,(x->>'machine')::uuid,(x->>'independent')::uuid,'Normal isolated transfer');
 perform pg_temp.ok((select ended_at is null from public.production_transfers where id=t),'normal existing transfer works without maintenance');
 perform mp_test.command(f,r,'propose',jsonb_build_object('start',start_at,'reason','Review borrowed machine'),3,gen_random_uuid());
 perform pg_temp.fails(format('select mp_test.command(%L,%L,''confirm'',''{}'',4,gen_random_uuid())',f,r),'maintenance_transfer_unresolved');
 perform public.stop_machine(f,(x->>'independent')::uuid,'planned',null,'inspection','Stopped borrower remains borrowed');
 perform pg_temp.ok((select ended_at is null from public.production_transfers where id=t),'stopped alternative never ends OPEN transfer');
 perform pg_temp.ok((select line_id is null from public.work_centers where id=(x->>'independent')::uuid),'permanent independent assignment unchanged');
 -- Emergency physical stop is always recordable and invalidates readiness only.
 x:=mp_test.fixture('emergency');f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;sid:=mp_test.plan(x,start_at);
 perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());
 insert into public.downtime_reasons(factory_id,name,name_ar) values(f,'Local breakdown','عطل محلي') returning id into reason;
 perform public.stop_machine(f,(x->>'machine')::uuid,'unplanned',reason,null,'Real explicit test transition');
 perform pg_temp.ok((select status='stopped' from public.work_centers where id=(x->>'machine')::uuid),'physical emergency stop remains allowed');
 perform pg_temp.ok((select state='INVALIDATED' and confirmed_at is not null from public.maintenance_schedules where id=sid),'emergency invalidates readiness without rewriting approval');
 perform pg_temp.ok((select count(*)=1 from public.downtime_events where factory_id=f and stop_nature='unplanned'),'one actual emergency event, no synthetic scheduling stop');
end$$;
select count(*)||' Maintenance transfer assertions passed' from assertions;
rollback;
