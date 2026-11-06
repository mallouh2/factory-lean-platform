-- Initial fictional configuration and protected workflow commands in a fresh cluster only.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55496 then raise exception 'Fresh Planning V3 localhost only';end if;end$$;
create schema planning_v3_test;
create table planning_v3_test.context(x jsonb);
do $$declare x jsonb;w jsonb;f uuid;pr uuid;i uuid;bad uuid;locked uuid;a timestamptz;begin
 x:=output4_test.context('PlanningV3');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'Planning V3 local factory','UTC',null);
 update public.production_lines set name='Printing line',name_ar='خط الطباعة' where id=(x->>'line')::uuid;
 update public.production_lines set name='Extrusion line',name_ar='خط البثق' where id=(x->>'other_line')::uuid;
 update public.products set name='Product X pipe',name_ar='أنبوب المنتج س' where id=(x->>'product')::uuid;
 w:=output4_test.decision(x,'COMPLETE',10);x:=x||jsonb_build_object('recovery',w->>'item_id');
 foreach bad in array array[gen_random_uuid(),gen_random_uuid(),gen_random_uuid()] loop
  pr:=public.create_production_request(f,'Small scheduling fixture','normal',clock_timestamp()+interval '7 days','Planning V3 controlled fixture',jsonb_build_array(jsonb_build_object('product_id',x->>'product','quantity',100,'unit','meter')));
  select id into i from public.production_orders where request_id=pr;
  if not x?'form' then x:=x||jsonb_build_object('form',i);
  elsif not x?'drag' then x:=x||jsonb_build_object('drag',i);
  else locked:=i;end if;
 end loop;
 a:=date_trunc('day',clock_timestamp())+interval '3 days 10 hours';
 perform public.plan_product_item(f,locked,(x->>'other_line')::uuid,a);
 perform public.set_plan_lock(f,locked,true);
 insert into public.production_lines(factory_id,name,name_ar,code) values(f,'Unconfigured line','خط غير مجهز','QA-NONE') returning id into bad;
 x:=x||jsonb_build_object('locked',locked,'invalid_line',bad);
 -- Restricted identity may inspect Orders/resources but cannot schedule. No global bypass.
 insert into public.user_permissions(factory_id,user_id,module,action)
 select f,(x->>'viewer')::uuid,module,action from public.permissions
 where module in ('orders','lines','centers') and action='view' on conflict do nothing;
 insert into planning_v3_test.context values(x);
end$$;
do $$begin
 if exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) then raise exception 'Late recording gate changed';end if;
end$$;
