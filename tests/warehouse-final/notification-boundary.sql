do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Local only';end if;end$$;
do $$declare x jsonb;f uuid;i integer;r jsonb;h private.manufactured_outputs;g jsonb;begin
 x:=late_test.new_context('warehouse-final-notice-boundary',14400,false);f:=(x->>'factory')::uuid;
 for i in 1..52 loop
  r:=public.record_manufactured_output(f,output2_test.payload(x,2),gen_random_uuid());select * into h from private.manufactured_outputs where entry_id=(r->>'entry_id')::uuid;
  g:=jsonb_build_array(h.recorded_groups->0||jsonb_build_object('quantity',case when i=1 then '2' else '1' end,'released',case when i=1 then '2' else '1' end));
  perform public.manufactured_output_command(f,'QUALITY',h.id,jsonb_build_object('groups',g,'rejected',case when i=1 then '0' else '1' end,'actual_rejected_kg',case when i=1 then '0' else '.5' end,'total','2','reason','Boundary inspection with measured evidence'),1,gen_random_uuid());
 end loop;
 r:=public.manufactured_output_read(f,'notifications');
 perform wh_final_test.ok(r->>'total'='51' and r->>'unread_count'='51' and jsonb_array_length(r->'rows')=50,'global unread count spans more than one page');
 r:=public.manufactured_output_read(f,'notifications',null,1);
 perform wh_final_test.ok(r->>'unread_count'='51' and jsonb_array_length(r->'rows')=1,'second page keeps authoritative global count');
end$$;
