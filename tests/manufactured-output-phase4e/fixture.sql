-- Initial conditions only. No output, receipt, issue, consumption or stock seed.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55495 then raise exception 'Fresh disposable localhost only';end if;end$$;
create schema output4e_test;
create table output4e_test.contexts(name text primary key,x jsonb);
do $$declare x jsonb;f uuid;s timestamptz;sid uuid;op uuid;label text;begin
 foreach label in array array['A','B','C'] loop
  x:=mp_test.fixture('P4E-'||label);f:=(x->>'factory')::uuid;
  perform public.update_settings(f,'Local acceptance '||label,'UTC',null);
  perform public.configure_working_calendar(f,127,'00:00','23:59');
  update public.products set name='Product X',name_ar='المنتج س' where id=(x->>'product')::uuid;
  update public.work_centers set name='Printing',name_ar='الطباعة' where id=(x->>'machine')::uuid;
  update public.work_center_categories set name='Printing',name_ar='الطباعة' where factory_id=f;
  perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
  s:=clock_timestamp()+interval '.3 seconds';sid:=public.configure_production_shift(f,'Acceptance shift','وردية القبول',s::time,(s+interval '8 hours')::time);
  perform pg_sleep(.4);
  insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid) returning id into op;
  insert into public.user_permissions(factory_id,user_id,module,action) select f,(x->>'worker')::uuid,'quality',a from unnest(array['view','create','edit']) a;
  insert into public.user_permissions(factory_id,user_id,module,action) select f,(x->>'viewer')::uuid,'warehouse',a from unnest(array['view','edit','issue']) a;
  insert into output4e_test.contexts values(label,x||jsonb_build_object('step1',op,'shift',sid,'scenario',label));
 end loop;
end$$;
create function output4e_test.payload(x jsonb,q numeric,w numeric default 0) returns jsonb language plpgsql as $$
declare p jsonb;g jsonb:='[]';begin
 p:=late_test.payload(x,q)||jsonb_build_object('confirm_overproduction',true,'unfinished',w,'remaining_work',case when w>0 then 'Printing remains' else '' end);
 if q>0 then g:=g||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',q::text,'missing_operations','[]'::jsonb));end if;
 if w>0 then g:=g||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',w::text,'missing_operations',jsonb_build_array(x->>'step1')));end if;
 return p||jsonb_build_object('output_groups',g);
end$$;
