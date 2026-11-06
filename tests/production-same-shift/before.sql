do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55497 then raise exception 'Owned same-shift fixture only';end if;end$$;
create schema same_shift_test;
create table same_shift_test.context(x jsonb);
create table same_shift_test.checks(label text);
create function same_shift_test.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL %',label;end if;insert into same_shift_test.checks values(label);end$$;
do $$declare x jsonb;s uuid;p jsonb;begin
 x:=late_test.new_context('same-shift-upgrade',14400,true);
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)values((x->>'factory')::uuid,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid)returning id into s;
 x:=x||jsonb_build_object('step1',s,'before_job',(select to_jsonb(o)from public.production_orders o where id=(x->>'item')::uuid));
 insert into same_shift_test.context values(x);
 p:=late_test.payload(x,2)||jsonb_build_object('output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity','2','missing_operations','[]'::jsonb)));
 perform late_test.fails(format('select public.record_manufactured_output(%L,%L,%L)',x->>'factory',p,gen_random_uuid()),'recording_disabled');
end$$;
