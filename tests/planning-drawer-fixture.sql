-- New resources only, on the established isolated QA copy. No identities/grants changed.
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499 or current_database()<>'factory_lean_quality_local' or current_setting('data_directory') not like '%FactoryLean-Compensation-Fix-%/data' then raise exception 'Disposable QA only';end if;end$$;
create schema if not exists planning_drawer_test;
create table if not exists planning_drawer_test.context(x jsonb);
do $$declare f uuid;actor uuid;cat uuid;p uuid;l uuid;m uuid;pr uuid;i uuid;kind text;result jsonb:='{}';x jsonb;r jsonb;begin
 if exists(select 1 from planning_drawer_test.context)then raise exception 'Fixture already exists; inspect saved state, do not recreate';end if;
 select c.x into x from wh_final_test.ui_context c limit 1;f:=(x->>'factory')::uuid;actor:=(x->>'owner')::uuid;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 foreach kind in array array['Printing','Extrusion']loop
 select id into cat from public.work_center_categories where factory_id=f and name=kind limit 1;
 if cat is null then raise exception 'Required existing machine category missing: %',kind;end if;
 insert into public.production_lines(factory_id,name,code)values(f,kind||' scheduling acceptance','PD-'||kind)returning id into l;
 insert into public.work_centers(factory_id,name,code,line_id,category_id,dependency_mode,impact_scope,status)
 values(f,kind||' acceptance machine','PD-'||kind,l,cat,'blocking','whole_line','idle')returning id into m;
 insert into public.products(factory_id,name,name_ar,code,unit,stock_unit,unit_weight_kg)
 values(f,kind||' scheduling pipe','أنبوب اختبار الجدولة','PD-'||kind,'meter','meter',.5)returning id into p;
 perform public.configure_center_capabilities(f,m,jsonb_build_array(jsonb_build_object('product_id',p,'rate',600,'rate_unit','meter','setup_minutes',1)));
 pr:=public.create_production_request(f,kind||' controlled scheduling','high',clock_timestamp()+interval '3 days','Disposable scheduling acceptance',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',10,'unit','meter')));
 select id into i from public.production_orders where request_id=pr;
 result:=result||jsonb_build_object(lower(kind),jsonb_build_object('item',i,'line',l,'product',p,'machine',m));
 end loop;
 x:=compensation_test.unreceived_fixture('pd-replace',true);
 r:=public.plan_quality_production(f,(x->>'output')::uuid,'{"quantity":"6","mode":"PLANNED"}',2,gen_random_uuid());
 result:=result||jsonb_build_object('replacement',jsonb_build_object('item',r#>>'{replacement,item_id}','line',x->>'line','original',x->>'item','original_target','909'),'factory',f,'owner',actor);
 insert into planning_drawer_test.context values(result);
end$$;
select x from planning_drawer_test.context;
