do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port() not in (55490,55491) then raise exception 'Disposable Phase4 localhost only';end if;end$$;
create schema output4_test;
create function output4_test.context(label text,two boolean default false) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;s1 uuid;s2 uuid;p jsonb;r jsonb;h private.manufactured_outputs;g jsonb;begin
 x:=late_test.new_context(label,14400,false);f:=(x->>'factory')::uuid;
 perform public.configure_center_capabilities(f,(x->>'other_machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid) returning id into s1;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,2,'work_center',(x->>'other_machine')::uuid) returning id into s2;
 x:=x||jsonb_build_object('step1',s1,'step2',s2);
 p:=output2_test.payload(x,90,10);p:=jsonb_set(p,'{output_groups}',jsonb_build_array(p->'output_groups'->0,jsonb_build_object('id',gen_random_uuid(),'quantity','10','missing_operations',case when two then jsonb_build_array(s2,s1) else jsonb_build_array(s1) end)));
 r:=public.record_manufactured_output(f,p,gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
 select jsonb_agg(value||jsonb_build_object('released',value->>'quantity')) into g from jsonb_array_elements(h.recorded_groups);
 perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'rejected','0','reason','Phase4 fixture inspected'),1,gen_random_uuid());
 perform public.receive_manufactured_output(f,h.id,jsonb_build_object('group_id',g->0->>'id','quantity',g->0->>'quantity','location','Finished bay','physical_confirmation',true),2,gen_random_uuid());
 perform public.receive_manufactured_output(f,h.id,jsonb_build_object('group_id',g->1->>'id','quantity',g->1->>'quantity','location','Recovery bay','physical_confirmation',true),3,gen_random_uuid());
 perform public.finish_product_item(f,(x->>'item')::uuid);
 return x||jsonb_build_object('output',h.id,'group',(select group_id from private.manufactured_output_lots where output_id=h.id),'lot',(select lot_id from private.manufactured_output_lots where output_id=h.id),'revision',4);
end$$;
create function output4_test.decision(x jsonb,choice text,q numeric,ops jsonb default null) returns jsonb language sql as $$
 select public.plan_manufactured_completion((x->>'factory')::uuid,(x->>'output')::uuid,jsonb_build_object('group_id',x->>'group','quantity',q::text,'choice',choice,'operations',coalesce(ops,case when choice='REPLACE' then '[]'::jsonb else jsonb_build_array(x->>'step1') end),'reason','Controlled Phase4 allocation'),(x->>'revision')::bigint,gen_random_uuid())
$$;
create function output4_test.start(x jsonb,w jsonb) returns jsonb language plpgsql as $$
declare f uuid:=(x->>'factory')::uuid;i uuid:=(w->>'item_id')::uuid;begin
 perform public.plan_product_item(f,i,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '5 days 1 hour');
 if w->>'material_request_id' is not null then perform public.supply_command(f,'material_change',jsonb_build_object('id',w->>'material_request_id','revision',1,'action','issue','reason','Issue actual stored input'),gen_random_uuid());end if;
 perform public.start_product_item(f,i);return x||jsonb_build_object('item',i);
end$$;
create function output4_test.receive(f uuid,entry uuid) returns jsonb language plpgsql as $$
declare h private.manufactured_outputs;g jsonb;v jsonb;rev integer:=2;begin
 select * into h from private.manufactured_outputs where factory_id=f and entry_id=entry;
 select jsonb_agg(value||jsonb_build_object('released',value->>'quantity')) into g from jsonb_array_elements(h.recorded_groups);
 perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'rejected','0','reason','Recovered output inspection'),1,gen_random_uuid());
 for v in select value from jsonb_array_elements(g) loop
 perform public.receive_manufactured_output(f,h.id,jsonb_build_object('group_id',v->>'id','quantity',v->>'quantity','location','Inspected recovery','physical_confirmation',true),rev,gen_random_uuid());rev:=rev+1;end loop;
 return jsonb_build_object('output',h.id,'group',g->0->>'id','lot',(select lot_id from private.manufactured_output_lots where output_id=h.id limit 1),'revision',rev);
end$$;
