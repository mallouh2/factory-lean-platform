-- New resources/records only in the verified cold-cloned disposable database.
do $$declare protected boolean;begin
 if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55500 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable end-recording clone only';end if;
 with recursive affected(oid)as(select 'private.production_shift_schedule_revisions'::regclass::oid union select conrelid from pg_constraint c join affected a on c.confrelid=a.oid where c.contype='f')
 select bool_or(n.nspname='auth'or c.relname in('users','memberships','roles','role_permissions','user_permissions','permission_packages','permission_package_permissions','member_permission_packages','factories'))into protected from affected a join pg_class c on c.oid=a.oid join pg_namespace n on n.oid=c.relnamespace;
 if protected then raise exception 'Operational reset would affect identity or permissions';end if;
end$$;
-- This is test-data disposal, never a production migration or history repair.
-- It avoids fabricating a current occurrence in inherited historical schedules.
truncate private.production_shift_schedule_revisions,public.production_shifts cascade;
truncate compensation_test.contexts;
create schema production_end_test;
create table production_end_test.contexts(label text primary key,x jsonb);
do $$declare x jsonb;sid uuid;stamp timestamptz:=clock_timestamp();begin
 select c.x into x from wh_final_test.ui_context c limit 1;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 sid:=public.configure_production_shift((x->>'factory')::uuid,'End recording acceptance','وردية اختبار إنهاء الإنتاج',(stamp+interval '1 second')::time,(stamp+interval '4 hours')::time);
 insert into compensation_test.contexts values('__end_base',x||jsonb_build_object('shift',sid));
 perform pg_sleep(1.2);
end$$;
create function production_end_test.fixture(label text,quantity numeric,initial_good numeric,sales boolean default false)returns jsonb language plpgsql as $$
declare x jsonb;f uuid;l uuid;m uuid;cat uuid;p uuid;step uuid;pr uuid;i uuid;so uuid;payload jsonb;receipt jsonb;begin
 select c.x into x from wh_final_test.ui_context c limit 1;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',true);
 insert into public.production_lines(factory_id,name,name_ar,code)values(f,'End recording '||label,'اختبار تسجيل الإنتاج '||label,'END-'||label)returning id into l;
 select id into cat from public.work_center_categories where factory_id=f and name='Printing';
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope,status)values(f,'End printer '||label,'END-'||label,l,cat,'blocking','whole_line','running')returning id into m;
 insert into public.products(factory_id,name,name_ar,code,unit,stock_unit,unit_weight_kg)values(f,'End recording pipe '||label,'أنبوب اختبار تسجيل الإنتاج '||label,'END-'||label,'meter','meter',.5)returning id into p;
 perform public.configure_center_capabilities(f,m,jsonb_build_array(jsonb_build_object('product_id',p,'rate',6000,'rate_unit','meter','setup_minutes',0)));
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values(f,p,1,'work_center',m)returning id into step;
 if sales then
  so:=public.create_sales_order(f,jsonb_build_object('customer_reference','End recording acceptance','requested_delivery',clock_timestamp()+interval '7 days','lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',quantity,'unit','meter'))),gen_random_uuid());
  perform public.approve_sales_order(f,so,gen_random_uuid());
  select id,request_id into i,pr from public.production_orders where factory_id=f and product_id=p;
 else
  pr:=public.create_production_request(f,'End recording '||label,'normal',null,'Controlled disposable fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',quantity,'unit','meter')));
  select id into i from public.production_orders where request_id=pr;
 end if;
 perform public.plan_product_item(f,i,l,clock_timestamp()+interval '1 minute');perform public.start_product_item(f,i);
 x:=x||jsonb_build_object('factory',f,'line',l,'machine',m,'product',p,'item',i,'request',pr,'step1',step,'sales',so);
 if initial_good>0 then
  payload:=late_test.payload(x,initial_good)||jsonb_build_object('output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',initial_good::text,'missing_operations','[]'::jsonb)));
  receipt:=public.record_manufactured_output(f,payload,gen_random_uuid());x:=x||jsonb_build_object('initial_receipt',receipt);
 end if;
 insert into production_end_test.contexts values(label,x);return x;
end$$;
select production_end_test.fixture('partial',6,2,true);
select production_end_test.fixture('none',6,2);
select production_end_test.fixture('cancel',6,2);
select production_end_test.fixture('retry',6,2);
select production_end_test.fixture('zero',2,2);
select production_end_test.fixture('stock',6,2);
do $$declare x jsonb;r jsonb;work jsonb;i uuid;rev bigint;begin
 x:=compensation_test.fixture('end-replacement',true,true);
 r:=compensation_test.replace(x,5);i:=(r->>'item_id')::uuid;
 perform public.plan_product_item((x->>'factory')::uuid,i,(x->>'line')::uuid,clock_timestamp()+interval '1 minute');perform public.start_product_item((x->>'factory')::uuid,i);
 insert into production_end_test.contexts values('replacement',x||jsonb_build_object('origin_item',x->>'item','item',i));
 x:=compensation_test.fixture('end-completion');perform public.finish_product_item((x->>'factory')::uuid,(x->>'item')::uuid);
 rev:=(x->>'revision')::bigint;
 work:=public.plan_manufactured_completion((x->>'factory')::uuid,(x->>'output')::uuid,jsonb_build_object('group_id',x->>'unfinished','quantity','4','choice','COMPLETE','operations',jsonb_build_array(x->>'step1'),'reason','Complete controlled unfinished material'),rev,gen_random_uuid());i:=(work->>'item_id')::uuid;
 perform public.plan_product_item((x->>'factory')::uuid,i,(x->>'line')::uuid,clock_timestamp()+interval '1 minute');
 select revision into rev from public.material_requests where id=(work->>'material_request_id')::uuid;
 perform public.supply_command((x->>'factory')::uuid,'material_change',jsonb_build_object('id',work->>'material_request_id','revision',rev,'action','issue','reason','Identified test material issued'),gen_random_uuid());
 perform public.start_product_item((x->>'factory')::uuid,i);
 insert into production_end_test.contexts values('completion',x||jsonb_build_object('origin_item',x->>'item','item',i,'work',work));
end$$;
