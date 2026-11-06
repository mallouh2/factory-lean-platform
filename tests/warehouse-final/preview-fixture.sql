-- Only the separate disposable SQL runtime; never the owner's manual preview.
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 or current_database()<>'factory_lean_quality_local' then raise exception 'Disposable warehouse acceptance only';end if;end$$;
create table if not exists wh_final_test.ui_context(x jsonb);
do $$declare x jsonb;f uuid;p jsonb;r jsonb;h private.manufactured_outputs;g jsonb;step1 uuid;step2 uuid;category uuid;ids jsonb:='[]';i integer;begin
 if exists(select 1 from wh_final_test.ui_context)then return;end if;
 x:=late_test.new_context('warehouse-final-ui',14400,false);f:=(x->>'factory')::uuid;
 insert into public.work_center_categories(factory_id,name,name_ar)values(f,'Printing','الطباعة')returning id into category;
 update public.work_centers set category_id=category where factory_id=f and id=(x->>'other_machine')::uuid;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid)returning id into step1;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values(f,(x->>'product')::uuid,2,'work_center',(x->>'other_machine')::uuid)returning id into step2;
 x:=x||jsonb_build_object('step1',step1,'step2',step2);
 for i in 1..4 loop
  p:=output2_test.payload(x,case when i=1 then 90 when i=2 then 20 else 10 end,0);
  if i=1 then p:=p||jsonb_build_object('unfinished',10,'remaining_work','Complete configured Printing','output_groups',jsonb_build_array(p->'output_groups'->0,jsonb_build_object('id',gen_random_uuid(),'quantity','10','missing_operations',jsonb_build_array(step2))));end if;
  r:=public.record_manufactured_output(f,p,gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
  select jsonb_agg(value||jsonb_build_object('released',value->>'quantity'))into g from jsonb_array_elements(h.recorded_groups);
  if i in(1,2)then select jsonb_agg(case when jsonb_array_length(value->'missing_operations')=0 then value||jsonb_build_object('quantity',case when i=1 then '89' else '19' end,'released',case when i=1 then '89' else '19' end)else value end)into g from jsonb_array_elements(g);end if;
  perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'rejected',case when i in(1,2)then '1' else '0' end,'actual_rejected_kg',case when i in(1,2)then '0.5' else '0' end,'total',case when i=1 then '100' when i=2 then '20' else '10' end,'reason',case when i in(1,2)then 'Measured rejected material; controlled local test' else 'Inspection matches actual production' end),1,gen_random_uuid());
  if i=4 then
   perform public.receive_manufactured_output(f,h.id,jsonb_build_object('group_id',g->0->>'id','quantity','10','location','QA held bay','physical_confirmation',true),2,gen_random_uuid());
   g:=jsonb_build_array(g->0||'{"quantity":"9","released":"9"}'::jsonb);
   perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'rejected','1','actual_rejected_kg','.5','total','10','reason','Observed damage after receipt; protected hold'),3,gen_random_uuid());
  end if;
  ids:=ids||jsonb_build_array(jsonb_build_object('output',h.id,'entry',h.entry_id,'finished',g->0->>'id','unfinished',g->1->>'id'));
 end loop;
 -- Existing unit-test viewer becomes an Orders-only observer in this new test
 -- factory. No pre-existing person/factory permission record is changed.
 insert into public.user_permissions(factory_id,user_id,module,action)values(f,(x->>'viewer')::uuid,'orders','view');
 insert into wh_final_test.ui_context values(x||jsonb_build_object('outputs',ids));
end$$;
select x from wh_final_test.ui_context;
