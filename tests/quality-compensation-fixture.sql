-- Test setup only: existing local actors, genuine current shift, protected commands.
-- Requires the established Phase4 local fixture schemas; creates no identities/grants.
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499 or current_database()<>'factory_lean_quality_local' or lower(replace(current_setting('data_directory'),chr(92),'/')) not like '%/factorylean-compensation-fix-%/data' then raise exception 'Verified disposable compensation copy only';end if;end$$;
create or replace function compensation_test.unreceived_fixture(label text,ended boolean default false,rejected_only boolean default false) returns jsonb language plpgsql as $$
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
 else sid:=(private.resolve_production_occurrence(f,clock_timestamp())#>>'{occurrence,shift_id}')::uuid;end if;
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
 -- Unreceived fixture: no lot or stock.
 x:=x||jsonb_build_object('output',o,'revision',2);
 insert into compensation_test.contexts values(label,x);return x;
end$$;
