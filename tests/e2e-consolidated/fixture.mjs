import fs from'node:fs';import{sql,c,root,guard,quote}from'./local.mjs';
if(fs.existsSync(root+'/acceptance-context.json'))throw Error('Fixture already exists');
const raw=sql(`begin;${guard}select set_config('request.jwt.claim.sub',${quote(c.context.owner)},true);
do $$declare f uuid:=${quote(c.context.factory)};p uuid;l uuid;l2 uuid;cat uuid;m uuid;m2 uuid;pr uuid;item uuid;short uuid;longjob uuid;sid uuid;begin
perform public.update_settings(f,'Isolated Consolidated QA','Asia/Qatar',null);perform public.configure_working_calendar(f,127,'00:00','23:59');
insert into public.production_lines(factory_id,name,code) values(f,'Consolidated Production','E2E1') returning id into l;insert into public.production_lines(factory_id,name,code) values(f,'Consolidated Scheduling','E2E2') returning id into l2;
insert into public.work_center_categories(factory_id,name) values(f,'Consolidated Extrusion') returning id into cat;
insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope,status) values(f,'Consolidated Extruder','E2E1',l,cat,'blocking','whole_line','running') returning id into m;
insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope,status) values(f,'Consolidated Scheduling Extruder','E2E2',l2,cat,'blocking','whole_line','idle') returning id into m2;
insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg) values(f,'Consolidated Test Pipe','E2E','meter','meter',.5) returning id into p;
insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes) values(f,m,p,60,'meter',0),(f,m2,p,60,'meter',0);
insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,p,1,'work_center',m);
sid:=public.configure_production_shift(f,'Consolidated Current','وردية الاختبار',((clock_timestamp() at time zone 'Asia/Qatar')-interval '15 minutes')::time,((clock_timestamp() at time zone 'Asia/Qatar')+interval '4 hours')::time);
pr:=public.create_production_request(f,'Consolidated acceptance','normal',null,'Isolated controlled fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',180,'unit','meter')));
select id into item from public.production_orders where request_id=pr and target_quantity=180;pr:=public.create_production_request(f,'Consolidated short','normal',null,'Controlled fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',1,'unit','meter')));select id into short from public.production_orders where request_id=pr;pr:=public.create_production_request(f,'Consolidated long','normal',null,'Controlled fixture',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',120,'unit','meter')));select id into longjob from public.production_orders where request_id=pr;
perform public.plan_product_item(f,item,l,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');perform public.start_product_item(f,item);
create table public.local_e2e_context(x jsonb);insert into public.local_e2e_context values(jsonb_build_object('factory',f,'owner',${quote(c.context.owner)},'worker',${quote(c.context.worker)},'viewer',${quote(c.context.viewer)},'product',p,'line',l,'schedule_line',l2,'machine',m,'item',item,'short',short,'long',longjob,'shift',sid,'request',pr));end$$;
select x from public.local_e2e_context;commit;`);
const x=JSON.parse(raw.split('\n').find(v=>v.startsWith('{')));fs.writeFileSync(root+'/acceptance-context.json',JSON.stringify(x,null,2));console.log(x);
