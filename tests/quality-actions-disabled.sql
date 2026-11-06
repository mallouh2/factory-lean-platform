-- Roll back the temporary predicate replacement; no activation record changes.
begin;
do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>55498 then raise exception 'Disposable local only';end if;end$$;
create or replace function private.manufactured_output_enabled(f uuid)returns boolean language sql stable set search_path='' as $$select false$$;
do $$declare x jsonb;o uuid;r jsonb;begin
 select c.x,c.output into x,o from qa_actions.context c limit 1;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 r:=public.production_quality_followups((x->>'factory')::uuid);
 if r->>'available'<>'false'or jsonb_typeof(r->'rows')<>'array'then raise exception 'Disabled reader contract';end if;
 perform late_test.fails(format('select public.production_quality_followup_command(%L,%L,%L,%L,0,%L)',x->>'factory',o,'START','{"quality_revision":1,"note":"Must remain disabled"}'::jsonb,gen_random_uuid()),'recording_disabled');
 raise notice 'Disabled read and write contracts PASS; rolling back fixture predicate';
end$$;
rollback;
