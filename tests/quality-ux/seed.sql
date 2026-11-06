-- Fresh disposable localhost fixture only. Never apply to hosted/retained factory data.
do $$declare x jsonb;f uuid;p jsonb;row jsonb;source uuid;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;
 select c.x into x from local_preview.context c;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);perform set_config('request.jwt.claim.role','authenticated',true);
 p:=late_test.payload(x,475)||jsonb_build_object('confirm_overproduction',true);
 row:=public.record_lean_production(f,p,gen_random_uuid());
 update local_preview.context c set x=c.x||jsonb_build_object('quality_entry',row->>'entry_id');
 for source in select id from public.finished_goods_sources where factory_id=f loop
  perform public.source_stock_command(f,'identify',jsonb_build_object('source',source,'quantity',(select quantity_credited::text from public.finished_goods_sources where id=source),'label',case when (select entry_id from public.finished_goods_sources where id=source)=(row->>'entry_id')::uuid then 'QA Quality Batch B' else 'QA Quality Batch A' end,'physically_identified',true),'[]',gen_random_uuid());
 end loop;
 perform public.quality_command(f,'reason',jsonb_build_object('name','QA measurement defect','name_ar','عيب القياس للاختبار','active',true),gen_random_uuid());
 insert into public.user_permissions(factory_id,user_id,module,action)values(f,(x->>'worker')::uuid,'quality','view'),(f,(x->>'worker')::uuid,'quality','create'),(f,(x->>'worker')::uuid,'quality_history','view');
end$$;
