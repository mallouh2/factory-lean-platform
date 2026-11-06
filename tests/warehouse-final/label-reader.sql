do $$declare x jsonb;r jsonb;f uuid;begin
 select t.x into x from wh_final_test.ui_context t;f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',false);
 r:=public.manufactured_receiving_context(f,(x#>>'{outputs,0,output}')::uuid);
 perform wh_final_test.ok(r#>>array['rows','0','operations',x->>'step2','name']='Printing','direct receipt uses configured operation name');
 r:=public.manufactured_receiving_read(f);
 perform wh_final_test.ok(exists(select 1 from jsonb_array_elements(r->'rows')v where v#>>array['operations',x->>'step2','name_ar']='الطباعة'),'queue uses authoritative Arabic operation name');
 perform wh_final_test.ok(has_function_privilege('authenticated','public.manufactured_receiving_context(uuid,uuid,integer)','execute')and not has_function_privilege('anon','public.manufactured_receiving_context(uuid,uuid,integer)','execute'),'receipt reader execution grants remain authenticated only');
end$$;
