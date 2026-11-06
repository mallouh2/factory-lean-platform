-- Give existing rollback suites a dedicated disposable demo factory and people.
-- Their comments say TESTING, but this runner never connects to hosted services.
do $$declare x jsonb;f uuid;label text;begin
 if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local fixture only';end if;
 x:=mp_test.fixture('platform-regression');f:=(x->>'factory')::uuid;
 update public.factories set is_demo=true where id=f;
 foreach label in array array['Mechanical Failure','Electrical Failure','Material Shortage','Quality Problem','Setup / Changeover','Utilities','Other','Planned Maintenance'] loop
  if not exists(select 1 from public.downtime_reasons where factory_id=f and name=label and parent_id is null) then
   perform public.lean_command(f,gen_random_uuid(),'cause',jsonb_build_object('id',gen_random_uuid(),'name',label));
  end if;
 end loop;
end$$;
