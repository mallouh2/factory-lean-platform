-- Local synthetic database fixtures, never a hosted Auth account or remote seed.
create schema quality_test;
create table quality_test.fixtures(name text primary key,factory_id uuid,actor_id uuid,technician_id uuid,
 product_id uuid,item_id uuid,line_id uuid,entry_id uuid);
create function quality_test.make_fixture(label text,u text,weight numeric,good numeric,wip numeric default 0,shared_legacy boolean default false) returns void
language plpgsql as $$
declare f uuid;a uuid;t uuid;p uuid;l uuid;c uuid;w uuid;r uuid;i uuid;e uuid;begin
 insert into auth.users(id,email,email_confirmed_at) values(gen_random_uuid(),label||'@isolated.invalid',now()) returning id into a;
 perform set_config('request.jwt.claim.sub',a::text,true);perform set_config('request.jwt.claim.role','authenticated',true);
 insert into public.factories(name) values('Isolated Quality '||label) returning id into f;
 insert into public.memberships(factory_id,user_id,display_name,is_owner,status) values(f,a,'Isolated fixture',true,'approved') returning id into t;
 insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Quality pipe','Q-'||label,u,u,weight) returning id into p;
 insert into public.production_lines(factory_id,name,code) values(f,'Quality line','Q1') returning id into l;
 insert into public.work_center_categories(factory_id,name) values(f,'Quality extrusion') returning id into c;
 insert into public.work_centers(factory_id,name,code,line_id,category_id) values(f,'Quality extruder','Q1',l,c) returning id into w;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(f,w,p,100,u);
 if shared_legacy then
  -- A legacy shared scheduled job is eligible for Sales allocation in the existing worker.
  -- Build that historical origin at insertion; never rewrite an immutable request origin.
  insert into public.production_requests(factory_id,code,name,requested_by,requested_by_name,priority,request_type)
   values(f,'','Legacy shared fixture',a,'Isolated fixture','normal',null) returning id into r;
  insert into public.production_orders(factory_id,request_id,product_id,target_quantity,unit) values(f,r,p,1000,u);
 else
  r:=public.create_production_request(f,'Quality fixture','normal',null,'Isolated local SQL fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1000,'unit',u)));
 end if;
 select id into i from public.production_orders where request_id=r;
 update public.production_orders set line_id=l,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=i;
 perform public.start_product_item(f,i);
 e:=(public.record_lean_production(f,jsonb_build_object('unit_kind','line','production_unit',l,'item',i,'technician',t,
  'good',good,'discarded_quantity',0,'scrap_kg',0,'unfinished',wip,'remaining_work',case when wip>0 then 'Final inspection' else '' end,'input_quantity',0),gen_random_uuid())->>'id')::uuid;
 insert into quality_test.fixtures values(label,f,a,t,p,i,l,e);
end$$;
select quality_test.make_fixture('legacy','meter',0.35,100);
