do $$declare x jsonb;f uuid;r jsonb;h uuid;p jsonb;q jsonb;step uuid;begin
x:=late_test.new_context('unified-mass-coexist',3600,false);f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid)returning id into step;
r:=public.record_manufactured_output(f,output2_test.payload(x,909)||'{"scrap_kg":0.2}',gen_random_uuid());select id into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','890','released','890','missing_operations','[]'::jsonb),jsonb_build_object('id',gen_random_uuid(),'quantity','10','released','10','missing_operations',jsonb_build_array(step),'restriction','Store separately')),'rejected','9','total','909','actual_rejected_kg','4.8','reason','Measured rejected material excludes0.2kg already recorded by Production');
perform public.manufactured_output_command(f,'QUALITY',h,p,1,gen_random_uuid());q:=public.quality_read(f,'{"mode":"board"}');
perform ux_test.ok((q->>'quality_scrap_kg')::numeric=4.8 and (select effective_scrap_kg=0.2 from public.production_entries where id=(r->>'entry_id')::uuid),'separate0.2 Production Scrap plus4.8 latest Quality Scrap; no9kg conversion');
perform set_config('request.jwt.claim.sub',x->>'viewer',false);perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,2,%L)',f,h,p,gen_random_uuid()),'permission_denied');
perform set_config('request.jwt.claim.sub',x->>'owner',false);perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,2,%L)',gen_random_uuid(),h,p,gen_random_uuid()),'permission_denied');
end$$;
