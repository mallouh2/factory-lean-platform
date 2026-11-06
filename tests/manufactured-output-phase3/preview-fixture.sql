do $$declare x jsonb;f uuid;r jsonb;h private.manufactured_outputs;groups jsonb;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55489 then raise exception 'Isolated preview only';end if;
 select a.x into x from output2_test.fixture a;f:=(x->>'factory')::uuid;
 if exists(select 1 from private.manufactured_outputs where factory_id=f) then raise exception 'Fixture already populated';end if;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 r:=public.record_manufactured_output(f,output2_test.payload(x,100),gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
 groups:=jsonb_build_array(jsonb_build_object('id',h.recorded_groups->0->>'id','quantity','95','released','95','missing_operations','[]'::jsonb));
 perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',groups,'rejected','5','reason','Five meters rejected; remaining output released'),1,gen_random_uuid());
end$$;
