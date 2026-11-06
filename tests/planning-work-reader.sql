-- Rollback-only fixtures use existing protected creation commands; no grants or gates change.
begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55499
 or current_database()<>'factory_lean_quality_local' or current_setting('data_directory') not like '%FactoryLean-Compensation-Fix-%/data'
 then raise exception 'Disposable QA only';end if;end$$;
do $$declare x jsonb;f uuid;actor uuid;out_id uuid;v jsonb;r jsonb;first_page jsonb;second_page jsonb;before_count integer;begin
 select c.x into x from planning_drawer_test.context c;f:=(x->>'factory')::uuid;actor:=(x->>'owner')::uuid;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 before_count:=(public.manufactured_planning_work_read(f)->>'total')::integer;
 x:=compensation_test.unreceived_fixture('planning-metadata-pagination',true);out_id:=(x->>'output')::uuid;
 for i in 1..105 loop
  v:=private.production_compensation_state(f,out_id);
  r:=public.plan_quality_production(f,out_id,'{"quantity":"0.01","mode":"PLANNED"}',(v->>'revision')::bigint,gen_random_uuid());
  if r#>>'{replacement,item_id}' is null then raise exception 'Fixture replacement missing';end if;
 end loop;
 first_page:=public.manufactured_planning_work_read(f);
 if (first_page->>'total')::integer<>before_count+105 or jsonb_array_length(first_page->'work')<>100 or not(first_page->>'has_more')::boolean then raise exception 'First100 pagination failed';end if;
 second_page:=public.manufactured_planning_work_read(f,(first_page#>>'{work,99,item_id}')::uuid);
 if second_page->>'context_hash'<>first_page->>'context_hash' or jsonb_array_length(second_page->'work')<>before_count+5 or(second_page->>'has_more')::boolean then raise exception 'Tail page/completeness failed';end if;
 if exists(select 1 from jsonb_array_elements(first_page->'work') a join jsonb_array_elements(second_page->'work') b on a->>'item_id'=b->>'item_id') then raise exception 'Duplicate metadata';end if;
 raise notice 'PASS protected105 replacement creations; metadata100+tail, same context, no duplicates';
 -- Context changes are visible, never silently combined by the collector.
 v:=private.production_compensation_state(f,out_id);
 perform public.plan_quality_production(f,out_id,'{"quantity":"0.01","mode":"PLANNED"}',(v->>'revision')::bigint,gen_random_uuid());
 if public.manufactured_planning_work_read(f)->>'context_hash'=first_page->>'context_hash' then raise exception 'Changing work context not detected';end if;
 raise notice 'PASS inter-page work change invalidates context';
 if has_function_privilege('anon','public.manufactured_planning_work_read(uuid,uuid)','EXECUTE') then raise exception 'Anonymous execute';end if;
 if not has_function_privilege('authenticated','public.manufactured_planning_work_read(uuid,uuid)','EXECUTE') then raise exception 'Authenticated grant absent';end if;
 raise notice 'PASS minimal RPC grants';
end$$;
select set_config('qa.factory',x->>'factory',true),set_config('qa.owner',x->>'owner',true),set_config('qa.worker',x->>'worker',true) from wh_final_test.ui_context limit 1;
select set_config('qa.foreign',(select id::text from public.factories where id<>current_setting('qa.factory')::uuid limit 1),true);
set local role authenticated;
do $$declare f uuid:=current_setting('qa.factory')::uuid;r jsonb;begin
 perform set_config('request.jwt.claim.sub',current_setting('qa.owner'),true);
 r:=public.manufactured_planning_work_read(f);
 if not(r->>'available')::boolean then raise exception 'Authorized owner reader unavailable';end if;
 raise notice 'PASS real authenticated owner SQL read';
 begin perform public.manufactured_planning_work_read(current_setting('qa.foreign')::uuid);raise exception 'Expected factory denial';exception when insufficient_privilege then null;end;
 raise notice 'PASS known foreign-factory scope denied by SQL';
 perform set_config('request.jwt.claim.sub',current_setting('qa.worker'),true);
 begin perform public.manufactured_planning_work_read(f);raise exception 'Expected missing Orders permission denial';exception when insufficient_privilege then null;end;
 raise notice 'PASS existing restricted worker denied by SQL';
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.manufactured_planning_work_read(f);raise exception 'Expected identity denial';exception when insufficient_privilege then null;end;
 raise notice 'PASS missing identity denied by SQL';
end$$;
reset role;
rollback;
