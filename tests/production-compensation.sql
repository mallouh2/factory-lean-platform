-- Fresh fixtures only; existing users, no historical shifts or owner records changed.
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable compensation tests only';end if;end$$;
create schema if not exists compensation_test;
create table if not exists compensation_test.contexts(label text primary key,x jsonb);
create table if not exists compensation_test.checks(label text primary key);
create or replace function compensation_test.ok(b boolean,label text) returns void language plpgsql as $$begin
 if b is distinct from true then raise exception 'FAIL %',label;end if;insert into compensation_test.checks values(label);raise notice 'PASS %',label;end$$;
create or replace function compensation_test.fixture(label text,ended boolean default false,rejected_only boolean default false) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;l uuid;cat uuid;m uuid;p uuid;step uuid;pr uuid;i uuid;sid uuid;stamp timestamptz;v jsonb;r jsonb;o uuid;g uuid:=gen_random_uuid();w uuid:=gen_random_uuid();q numeric;begin
 select c.x into x from wh_final_test.ui_context c limit 1;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 f:=(x->>'factory')::uuid;
 insert into public.production_lines(factory_id,name,code) values(f,'Compensation cell '||label,'CELL-'||label) returning id into l;
 select id into cat from public.work_center_categories where factory_id=f and name='Printing';
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope,status) values(f,'Printer '||label,'PRINT-'||label,l,cat,'blocking','whole_line','running') returning id into m;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Compensation pipe '||label,'COMP-'||label,'meter','meter',.5) returning id into p;
 perform public.configure_center_capabilities(f,m,jsonb_build_array(jsonb_build_object('product_id',p,'rate',6000,'rate_unit','meter','setup_minutes',0)));
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,p,1,'work_center',m) returning id into step;

 if not exists(select 1 from compensation_test.contexts) then
 stamp:=clock_timestamp()+interval '.2 seconds';sid:=public.configure_production_shift(f,'Current compensation acceptance','وردية التعويض',stamp::time,(stamp+interval '4 hours')::time);perform pg_sleep(.3);
 else sid:=(select (c.x->>'shift')::uuid from compensation_test.contexts c limit 1);end if;
 q:=case when rejected_only then 100 else 909 end;
 pr:=public.create_production_request(f,'Compensation original','normal',null,'Fresh acceptance',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',q,'unit','meter')));
 select id into i from public.production_orders where request_id=pr;
 perform public.plan_product_item(f,i,l,clock_timestamp()+interval '1 minute');perform public.start_product_item(f,i);
 x:=x||jsonb_build_object('factory',f,'line',l,'machine',m,'product',p,'item',i,'shift',sid,'step1',step,'finished',g,'unfinished',w);
 v:=late_test.payload(x,q)||jsonb_build_object('output_groups',jsonb_build_array(jsonb_build_object('id',g,'quantity',q::text,'missing_operations','[]'::jsonb)));
 r:=public.record_manufactured_output(f,v,gen_random_uuid());select id into o from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
 if ended then perform public.finish_product_item(f,i);end if;
 v:=jsonb_build_array(jsonb_build_object('id',g,'quantity',case when rejected_only then '95' else '903' end,'released',case when rejected_only then '95' else '903' end,'missing_operations','[]'::jsonb));
 if not rejected_only then v:=v||jsonb_build_array(jsonb_build_object('id',w,'quantity','4','released','4','missing_operations',jsonb_build_array(step)));end if;
 perform public.manufactured_output_command(f,'QUALITY',o,jsonb_build_object('groups',v,'rejected',case when rejected_only then '5' else '2' end,'total',q::text,'actual_rejected_kg',case when rejected_only then '2.5' else '1' end,'reason','Measured Quality result'),1,gen_random_uuid());
 if not rejected_only then perform public.receive_manufactured_output(f,o,jsonb_build_object('group_id',w,'quantity','4','location','Identified unfinished rack','physical_confirmation',true),2,gen_random_uuid());end if;
 x:=x||jsonb_build_object('output',o,'revision',case when rejected_only then 2 else 3 end);
 insert into compensation_test.contexts values(label,x);return x;
end$$;
create or replace function compensation_test.replace(x jsonb,q numeric,k uuid default gen_random_uuid()) returns jsonb language sql as $$
 select public.plan_production_compensation((x->>'factory')::uuid,(x->>'output')::uuid,jsonb_build_object('quantity',q::text,'mode',case when (select status from public.production_orders where id=(x->>'item')::uuid)='active' then 'ACTIVE' else 'PLANNED' end,'reason','Replace the identified Quality deficit'),(x->>'revision')::bigint,k)
$$;
create or replace function compensation_test.finish_output(x jsonb,q numeric,input jsonb default null) returns jsonb language plpgsql as $$
declare p jsonb;r jsonb;h uuid;g uuid:=gen_random_uuid();f uuid:=(x->>'factory')::uuid;begin
 p:=late_test.payload(x,q)||jsonb_build_object('confirm_overproduction',true,'output_groups',jsonb_build_array(jsonb_build_object('id',g,'quantity',q::text,'missing_operations','[]'::jsonb)))||coalesce(input,'{}'::jsonb);
 r:=public.record_manufactured_output(f,p,gen_random_uuid());select id into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
 perform public.manufactured_output_command(f,'QUALITY',h,jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',g,'quantity',q::text,'released',q::text,'missing_operations','[]'::jsonb)),'rejected','0','reason','Replacement inspected'),1,gen_random_uuid());
 return r||jsonb_build_object('output',h,'group',g);
end$$;
do $$declare x jsonb;r jsonb;p jsonb;f uuid;k uuid:=gen_random_uuid();lot uuid;j public.production_orders;s jsonb;begin
 x:=compensation_test.fixture('active-all');f:=(x->>'factory')::uuid;
 s:=public.production_compensation_read(f,(x->>'output')::uuid);
 perform compensation_test.ok(s->>'available'='6' and s->>'accepted'='903' and s->>'received'='0','accepted but unreceived output is covered');
 select * into j from public.production_orders where id=(x->>'item')::uuid;
 r:=compensation_test.replace(x,6,k);
 perform compensation_test.ok((r->>'item_id')::uuid=j.id and r->>'mode'='ACTIVE' and (select count(*)=1 from public.production_orders where factory_id=f and product_id=j.product_id),'active replacement uses same job');
 perform compensation_test.ok(compensation_test.replace(x,6,k)=r,'exact allowance retry is idempotent');
 perform late_test.fails(format('select compensation_test.replace(%L::jsonb,5,%L)',x,k),'request_conflict');
 select lot_id into lot from private.manufactured_output_lots where factory_id=f and output_id=(x->>'output')::uuid;
 perform compensation_test.ok((select warehouse_quantity=4 and quantity_available=4 from public.unfinished_lots where id=lot) and (select assigned=4 and replaced=4 from private.output_work_allocations(f,lot)),'replace all releases entitlement but preserves physical four');
 p:=compensation_test.finish_output(x,6);
 perform compensation_test.ok(private.compensation_recorded(f,j.id)=6 and (select target_quantity=909 and actual_start=j.actual_start and start_time=j.start_time and expected_finish=j.expected_finish from public.production_orders where id=j.id),'extra six attributed without target or timestamp change');
 perform compensation_test.ok(private.output_demand_received(f,j.id)=0,'recording and approval do not credit receipts');
 perform public.receive_manufactured_output(f,(x->>'output')::uuid,jsonb_build_object('group_id',x->>'finished','quantity','903','location','Original identified output','physical_confirmation',true),4,gen_random_uuid());
 perform public.receive_manufactured_output(f,(p->>'output')::uuid,jsonb_build_object('group_id',p->>'group','quantity','6','location','Replacement identified output','physical_confirmation',true),2,gen_random_uuid());
 perform compensation_test.ok(private.output_demand_received(f,j.id)=909 and (select on_hand=909 from public.finished_goods_balances where factory_id=f and product_id=j.product_id),'903 plus real replacement receipt six fulfills exactly909');
 x:=x||jsonb_build_object('revision',(select max(revision)from private.manufactured_output_events where output_id=(x->>'output')::uuid));perform late_test.fails(format('select compensation_test.replace(%L::jsonb,1)',x),'output_demand_covered');
 perform public.finish_product_item(f,j.id);
 perform compensation_test.ok((select status='completed' and actual_finish is not null from public.production_orders where id=j.id),'active replacement ends normally');
end$$;
