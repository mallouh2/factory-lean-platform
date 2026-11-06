do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local disposable only';end if;end$$;
-- Local fixture replacement only; the shipped implementation is always FALSE.
create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet$$;
create schema output2_test;
create table output2_test.fixture(x jsonb);
do $$declare x jsonb;s1 uuid;s2 uuid;begin
 x:=late_test.new_context('output2',3600,false);
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values((x->>'factory')::uuid,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid) returning id into s1;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values((x->>'factory')::uuid,(x->>'product')::uuid,2,'work_center',(x->>'other_machine')::uuid) returning id into s2;
 insert into output2_test.fixture values(x||jsonb_build_object('step1',s1,'step2',s2));
end$$;
create function output2_test.payload(x jsonb,good numeric,wip numeric default 0) returns jsonb language plpgsql as $$
declare p jsonb;groups jsonb:='[]';begin
 p:=late_test.payload(x,good)||jsonb_build_object('confirm_overproduction',true,'unfinished',wip,'remaining_work',case when wip>0 then 'Complete selected operations' else '' end);
 if good>0 then groups:=groups||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',good::text,'missing_operations','[]'::jsonb));end if;
 if wip>0 then groups:=groups||jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',(wip*.6)::text,'missing_operations',jsonb_build_array(x->>'step1')),jsonb_build_object('id',gen_random_uuid(),'quantity',(wip*.4)::text,'missing_operations',jsonb_build_array(x->>'step2',x->>'step1')));end if;
 return p||jsonb_build_object('output_groups',groups);
end$$;
