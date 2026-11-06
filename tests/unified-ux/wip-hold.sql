do $$declare x jsonb;f uuid;w jsonb;p jsonb;g jsonb;r jsonb;begin
 x:=output4_test.context('unified-wip-hold');f:=(x->>'factory')::uuid;w:=output4_test.decision(x,'COMPLETE',5);
 select private.output_finding(f,(x->>'output')::uuid)->'groups' into g;
 select jsonb_agg(case when jsonb_array_length(v->'missing_operations')=0 then v||'{"quantity":"89","released":"89"}'::jsonb else v end)into g from jsonb_array_elements(g)v;
 p:=jsonb_build_object('groups',g,'total','100','rejected','1','actual_rejected_kg','.5','reason','New observed damage after receiving; hold before any physical adjustment');
 perform public.manufactured_output_command(f,'QUALITY',(x->>'output')::uuid,p,5,gen_random_uuid());r:=public.warehouse_stored_unfinished(f);
 perform ux_test.ok(r#>>'{rows,0,held}'='true' and r#>>'{rows,0,available}'='0' and r#>>'{rows,0,on_hand}'='10','held WIP has zero eligible availability while physical quantity is preserved');
end$$;
