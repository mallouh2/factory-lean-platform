begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Disposable local only';end if;end$$;
create or replace function private.manufactured_output_enabled(f uuid) returns boolean language sql stable set search_path='' as $$select false$$;
do $$declare x jsonb;s jsonb;begin
 select c.x into x from compensation_test.contexts c where label='security';perform set_config('request.jwt.claim.sub',x->>'owner',true);
 s:=public.production_compensation_read((x->>'factory')::uuid,(x->>'output')::uuid);
 if s->>'available'<>'0' or s->>'blocked_reason'<>'recording_disabled' then raise exception 'Disabled compensation reader';end if;
 perform late_test.fails(format('select compensation_test.replace(%L::jsonb,1)',x),'recording_disabled');
 raise notice 'PASS disabled authoritative read and write; rolling back temporary fixture predicate';
end$$;
rollback;
do $$begin
 perform compensation_test.ok(not has_function_privilege('anon','public.plan_production_compensation(uuid,uuid,jsonb,bigint,uuid)','execute')
 and not has_function_privilege('authenticated','private.production_compensation_state(uuid,uuid)','execute')
 and not has_table_privilege('authenticated','private.production_compensation','insert')
 and not has_table_privilege('authenticated','private.production_compensation_entries','update'),'private audit and helpers inaccessible; anonymous commands denied');
 perform late_test.fails('update private.production_compensation set reason=''Rewrite immutable decision''','manufactured_output_immutable');
 perform late_test.fails('delete from private.production_compensation_entries','manufactured_output_immutable');
end$$;
