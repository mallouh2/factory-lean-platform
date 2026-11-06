do $$declare x jsonb;r jsonb;w jsonb;f uuid;begin x:=output4_test.context('unified-wip-reader');f:=(x->>'factory')::uuid;r:=public.warehouse_stored_unfinished(f);
perform ux_test.ok(r#>>'{rows,0,on_hand}'='10' and r#>>'{rows,0,available}'='10','WIP storage separated from finished stock');
w:=output4_test.decision(x,'COMPLETE',5);r:=public.warehouse_stored_unfinished(f);perform ux_test.ok(r#>>'{rows,0,reserved}'='5' and r#>>'{rows,0,available}'='5','unfinished demand allocation reflected without double-counting stock');
perform set_config('request.jwt.claim.sub',x->>'viewer',false);perform late_test.fails(format('select public.warehouse_stored_unfinished(%L)',f),'permission_denied');end$$;
