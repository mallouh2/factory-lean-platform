-- Existing disposable regression context only; no owner preview transactions.
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Local only';end if;end$$;
do $$declare t record;f uuid;h private.manufactured_outputs;rev bigint;p jsonb;k uuid:=gen_random_uuid();r jsonb;c bigint;begin
 select * into t from ux_test.quality_context limit 1;f:=(t.x->>'factory')::uuid;select * into h from private.manufactured_outputs where id=t.output;
 perform set_config('request.jwt.claim.sub',t.x->>'owner',false);select max(revision)into rev from private.manufactured_output_events where output_id=h.id;
 p:=jsonb_build_object('groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','890','released','890','missing_operations','[]'::jsonb),jsonb_build_object('id',gen_random_uuid(),'quantity','10','released','10','missing_operations',jsonb_build_array(t.x->>'step1'),'restriction','Keep separate until operation complete')),'total','909','rejected','9','actual_rejected_kg','4.8','reason','Nine meters physically damaged; measured separately from Production Scrap');
 select count(*)into c from private.manufactured_output_events where output_id=h.id;
 r:=public.manufactured_output_command(f,'QUALITY',h.id,p,rev,k);
 perform ux_test.ok(r->>'actual_rejected_kg'='4.8' and r->>'rejected'='9','measured weight distinct from meters and theoretical4.5kg');
 perform ux_test.ok(public.manufactured_output_command(f,'QUALITY',h.id,p,rev,k)=r and (select count(*)=c+1 from private.manufactured_output_events where output_id=h.id),'mass UUID replay exactly one finding');
 perform ux_test.ok(private.output_rejected_mass(f,h.entry_id)=4.8 and (select effective_good=909 from public.production_entries where id=h.entry_id),'latest mass evidence and original Good unchanged');
 perform ux_test.ok(not exists(select 1 from public.finished_goods_movements where factory_id=f),'rejected mass creates no stock movement');
 perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,%s,%L)',f,h.id,p-'actual_rejected_kg',rev+1,gen_random_uuid()),'output_measured_weight');
 perform late_test.fails(format('select public.manufactured_output_command(%L,''QUALITY'',%L,%L,%s,%L)',f,h.id,p||'{"actual_rejected_kg":"-1"}',rev+1,gen_random_uuid()),'output_measured_weight');
end$$;
