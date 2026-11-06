do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Local only';end if;end$$;
do $$declare x jsonb;f uuid;r jsonb;p jsonb;entry uuid;op uuid;begin
 x:=output4_test.context('warehouse-final-pool',true);f:=(x->>'factory')::uuid;
 p:=output2_test.payload(x,90,10);
 -- The four-unit group is the same unordered operation set as the original
 -- ten-unit stored group, but the input array order is deliberately reversed.
 p:=jsonb_set(p,'{output_groups,2,missing_operations}',jsonb_build_array(x->>'step1',x->>'step2'));
 r:=public.record_manufactured_output(f,p,gen_random_uuid());entry:=(r->>'entry_id')::uuid;
 perform output4_test.receive(f,entry);r:=public.warehouse_stored_unfinished(f);
 perform wh_final_test.ok(exists(select 1 from jsonb_array_elements(r->'rows')v where v->>'on_hand'='14' and jsonb_array_length(v->'missing_operations')=2),'compatible unordered operation sets pool without losing source genealogy');
 perform wh_final_test.ok(exists(select 1 from jsonb_array_elements(r->'rows')v where v->>'on_hand'='6' and jsonb_array_length(v->'missing_operations')=1),'different missing-operation combinations remain separate');
 p:=output2_test.payload(x,90,10);p:=jsonb_set(p,'{output_groups,2,restriction}','"Keep segregated"'::jsonb);
 r:=public.record_manufactured_output(f,p,gen_random_uuid());perform output4_test.receive(f,(r->>'entry_id')::uuid);r:=public.warehouse_stored_unfinished(f);
 perform wh_final_test.ok(exists(select 1 from jsonb_array_elements(r->'rows')v where v->>'on_hand'='4' and v->>'restriction'='Keep segregated'),'different recovery restrictions are not pooled');
end$$;
