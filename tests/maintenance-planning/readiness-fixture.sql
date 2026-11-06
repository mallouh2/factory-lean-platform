-- Disposable loopback setup only. Commands under test use real public RPCs.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;end$$;
create function mp_test.released(label text,independent boolean default false,other_line boolean default false,verify boolean default true) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;r uuid;m uuid;sid uuid;a timestamptz;e uuid;p uuid;begin
 x:=mp_test.fixture(label);f:=(x->>'factory')::uuid;r:=(x->>'request')::uuid;m:=(x->>'machine')::uuid;
 if other_line then
 m:=(x->>'other_machine')::uuid;
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',m,'title','Other line service','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'assigned_to',x->>'worker'),gen_random_uuid());
 x:=x||jsonb_build_object('machine',m,'request',r,'line',x->>'other_line','other_machine',x->>'machine','other_line',x->>'line');
 elsif independent then
 m:=(x->>'independent')::uuid;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Independent QA product','MP-IN','meter','meter',.5) returning id into p;
 perform public.configure_center_capabilities(f,m,jsonb_build_array(jsonb_build_object('product_id',p,'rate',100,'rate_unit','meter','setup_minutes',1)));
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,p,1,'work_center',m);
 insert into public.production_routing_steps(factory_id,product_id,position,kind,line_id) values(f,(x->>'product')::uuid,1,'line',(x->>'line')::uuid);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 hour');
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',m,'title','Independent service','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'assigned_to',x->>'worker'),gen_random_uuid());
 x:=x||jsonb_build_object('machine',m,'request',r);
 end if;
 if not independent then perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '1 hour');end if;
 update private.maintenance_planning_activation set enabled=true;
 a:=clock_timestamp()+interval '.3 seconds';sid:=mp_test.plan(x,a,a+interval '5 minutes');
 perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());perform pg_sleep(.35);
 e:=public.stop_machine_for_maintenance(f,m,'planned',null,'inspection','Local readiness fixture',sid,2,2,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'worker',true);
 perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Inspected locally"}',3,gen_random_uuid());
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 perform public.change_status(f,m,'idle');
 if verify then perform public.change_maintenance_request(f,r,'verify','{"result":"RESOLVED","verification_note":"Independent local check"}',4,gen_random_uuid());end if;
 update private.maintenance_planning_activation set enabled=false;
 return x||jsonb_build_object('schedule',sid,'event',e);
end$$;
revoke all on function mp_test.released(text,boolean,boolean,boolean) from public,anon,authenticated;
