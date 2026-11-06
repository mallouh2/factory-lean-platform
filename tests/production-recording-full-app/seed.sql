-- Disposable localhost fixture only; never a hosted seed or application migration.
do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable loopback required';end if;end$$;
create schema local_preview;
create table local_preview.context(x jsonb);
do $$declare x jsonb;f uuid;sid uuid;tech uuid;entry uuid;second uuid;p jsonb;s timestamptz;begin
 x:=mp_test.fixture('visual-acceptance');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'Local Visual Acceptance Factory - SYNTHETIC','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 update public.production_lines set name=case when id=(x->>'line')::uuid then 'LINE A - Pressure pipes' else 'LINE B - Packaging' end,
  name_ar=case when id=(x->>'line')::uuid then 'الخط أ - أنابيب الضغط' else 'الخط ب - التغليف' end where factory_id=f;
 update public.work_centers set name_ar=case when line_id=(x->>'line')::uuid then 'ماكينة البثق الرئيسية' when line_id is null then 'ماكينة مستقلة' else 'ماكينة البثق الثانية' end where factory_id=f;
 update public.products set name='PE100 pressure pipe',name_ar='أنبوب ضغط PE100' where factory_id=f;
 update public.memberships set display_name=case when user_id=(x->>'owner')::uuid then 'Local acceptance owner' when user_id=(x->>'worker')::uuid then 'Local production technician' else 'Local restricted viewer' end where factory_id=f;
 insert into public.user_permissions(factory_id,user_id,module,action)values(f,(x->>'worker')::uuid,'orders','view'),(f,(x->>'worker')::uuid,'orders','edit'),(f,(x->>'viewer')::uuid,'lines','view');
 -- An occurrence valid across midnight while preserving the actual configured shift model.
 s:=clock_timestamp()+interval '.5 seconds';
 sid:=public.configure_production_shift(f,'Current production shift','وردية الإنتاج الحالية',s::time,(s+interval '23 hours')::time);
 perform pg_sleep(.6);
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 perform public.change_status(f,(x->>'machine')::uuid,'running');
 select id into tech from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 insert into local_preview.context values(x||jsonb_build_object('shift',sid,'technician',tech));
end$$;
-- A new statement is required: reader evaluation time must follow actual Start.
do $$declare x jsonb;f uuid;tech uuid;p jsonb;entry uuid;begin
 select c.x into x from local_preview.context c;f:=(x->>'factory')::uuid;tech:=(x->>'technician')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);perform set_config('request.jwt.claim.role','authenticated',true);
 select value into p from jsonb_array_elements(public.production_shift_work(f,null,100)->'rows')where value->>'item_id'=x->>'item';
 p:=jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',tech,'good',25,'discarded_quantity',0,'scrap_kg',0.75,'unfinished',2,'remaining_work','Finish cooling',
 'recording_context',jsonb_build_object('version',3,'execution_key',p->>'execution_key','context_hash',p->>'context_hash','occurrence_key',public.production_shift_work(f,null,100)#>>'{occurrence,occurrence_key}','current_shift_quantity_confirmed',true));
 entry:=(public.record_lean_production(f,p,gen_random_uuid())->>'entry_id')::uuid;
 if entry is null then raise exception 'Seed receipt missing';end if;
 update local_preview.context c set x=c.x||jsonb_build_object('entry',entry);
 if exists(select 1 from private.production_recording_v3_activation where enabled or schema_contract_version<>0) or exists(select 1 from private.maintenance_planning_activation where enabled)then raise exception 'Disabled gates required';end if;
end$$;
