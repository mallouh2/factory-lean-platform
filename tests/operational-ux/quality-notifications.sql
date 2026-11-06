do $$declare x jsonb;f uuid;o uuid;q jsonb;rev bigint;n bigint;p jsonb;begin
 select c.x,c.output into x,o from ux_test.quality_context c;f:=(x->>'factory')::uuid;perform set_config('request.jwt.claim.sub',x->>'owner',false);
 select max(revision)into rev from private.manufactured_output_events where output_id=o;
 n:=private.output_notification_revision(f,o);q:=private.output_finding(f,o);
 perform public.manufactured_output_command(f,'ACKNOWLEDGE',o,jsonb_build_object('quality_revision',n),rev,gen_random_uuid());
 p:=jsonb_build_object('groups',q->'groups','total',q->>'total','rejected',q->>'rejected','reason','Added supporting inspection note only');
 perform public.manufactured_output_command(f,'QUALITY',o,p,rev+1,gen_random_uuid());
 perform ux_test.ok(private.output_notification_revision(f,o)=n,'note-only revision does not create new Production notification');
 perform ux_test.ok(not exists(select 1 from jsonb_array_elements(public.manufactured_output_read(f,'notifications')->'rows')r where r->>'id'=o::text and r->>'unread'='true'),'previous acknowledgement survives note-only revision');
 perform ux_test.ok(not has_function_privilege('authenticated','private.output_material_signature(jsonb,numeric)','EXECUTE'),'private comparison helper not exposed');
end$$;
