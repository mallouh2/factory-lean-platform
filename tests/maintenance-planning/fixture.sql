-- Only installed by the disposable loopback runner. Never a hosted seed.
do $$begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;
end$$;
create schema mp_test;
create function mp_test.fixture(label text) returns jsonb language plpgsql as $$
declare f uuid;a uuid;worker uuid;viewer uuid;p uuid;l uuid;l2 uuid;c uuid;m uuid;m2 uuid;cat uuid;pr uuid;item uuid;r uuid;begin
 insert into auth.users values(gen_random_uuid(),label||'@local.invalid',now()) returning id into a;
 insert into auth.users values(gen_random_uuid(),label||'-worker@local.invalid',now()) returning id into worker;
 insert into auth.users values(gen_random_uuid(),label||'-viewer@local.invalid',now()) returning id into viewer;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claim.role','authenticated',true);
 insert into public.factories(name) values('Isolated Maintenance '||label) returning id into f;
 insert into public.memberships(factory_id,user_id,display_name,is_owner,status) values(f,a,'Local owner',true,'approved');
 insert into public.memberships(factory_id,user_id,display_name,status) values(f,worker,'Local worker','approved'),(f,viewer,'Local viewer','approved');
 insert into public.user_permissions(factory_id,user_id,module,action) values(f,worker,'factory','view'),(f,viewer,'factory','view'),(f,viewer,'maintenance','view');
 insert into public.production_lines(factory_id,name,code) values(f,'Maintenance test line','MP1') returning id into l;
 insert into public.production_lines(factory_id,name,code) values(f,'Unrelated line','MP2') returning id into l2;
 insert into public.work_center_categories(factory_id,name) values(f,'Extrusion') returning id into cat;
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope)
 values(f,'Main extruder','MP1',l,cat,'blocking','whole_line') returning id into m;
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope)
 values(f,'Other extruder','MP2',l2,cat,'blocking','whole_line') returning id into m2;
 insert into public.work_centers(factory_id,name,code,category_id,dependency_mode,impact_scope)
 values(f,'Independent equipment','MPI',cat,'independent','none') returning id into c;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Pipe','MP','meter','meter',.5) returning id into p;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes) values(f,m,p,100,'meter',5),(f,m2,p,100,'meter',5);
 pr:=public.create_production_request(f,'Local Maintenance production','normal',null,'Isolated fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',100,'unit','meter')));
 select id into item from public.production_orders where request_id=pr;
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',m,'title','Planned local service','priority','NORMAL','assigned_to',worker,'maintenance_kind','PLANNED','estimated_duration_minutes',1),gen_random_uuid());
 return jsonb_build_object('factory',f,'owner',a,'worker',worker,'viewer',viewer,'product',p,'line',l,'other_line',l2,'machine',m,'other_machine',m2,'independent',c,'item',item,'request',r);
end$$;

create function mp_test.plan(x jsonb,a timestamptz,b timestamptz default null) returns uuid language plpgsql as $$
declare sid uuid;begin
 perform public.maintenance_planning_command((x->>'factory')::uuid,(x->>'request')::uuid,'propose',jsonb_build_object('start',a,'end',coalesce(b,a+interval '1 minute')),0,gen_random_uuid());
 select id into sid from public.maintenance_schedules where maintenance_request_id=(x->>'request')::uuid;
 return sid;
end$$;

create function mp_test.command(f uuid,rid uuid,op text,p jsonb,rev integer,retry uuid) returns uuid
language plpgsql security definer set search_path='' as $$
declare r public.maintenance_requests;s public.maintenance_schedules;old public.maintenance_commands;v jsonb;a timestamptz;b timestamptz;begin
 if op in ('confirm','reschedule') and not (p ? 'context_hash') then
 select * into old from public.maintenance_commands where factory_id=f and request_id=retry;
 if found then p:=old.payload->'payload';else
 select * into r from public.maintenance_requests where factory_id=f and id=rid;
 select * into s from public.maintenance_schedules where factory_id=f and maintenance_request_id=rid;
 a:=case when op='confirm' then s.planned_start else (p->>'start')::timestamptz end;
 b:=case when op='confirm' then s.planned_end else coalesce((p->>'end')::timestamptz,a+make_interval(mins=>r.estimated_duration_minutes)) end;
 v:=public.maintenance_planning_preview(f,rid,a,b,r.revision,coalesce(s.revision,0));
 p:=p||jsonb_build_object('context_hash',v->>'context_hash','request_revision',r.revision);
 end if;end if;
 return public.maintenance_planning_command(f,rid,op,p,rev,retry);
end$$;
-- Authenticated legacy regressions use the test-only preview/retry adapter.
grant usage on schema mp_test to authenticated;
revoke all on function mp_test.fixture(text),mp_test.plan(jsonb,timestamptz,timestamptz),mp_test.command(uuid,uuid,text,jsonb,integer,uuid) from public,anon,authenticated;
grant execute on function mp_test.command(uuid,uuid,text,jsonb,integer,uuid) to authenticated;
