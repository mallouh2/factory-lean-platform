-- TESTING regression: compare retained content with the frozen full-history snapshot.
-- Temporary functions and all fixture changes are rolled back.
begin;
create function pg_temp.snapshot_previous(factory uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;data jsonb:='{}';limited text[]:='{}';
 query text:='';
 tabs text[]:=array[
   'areas','work_center_categories','production_lines','work_centers',
   'products','production_requests','production_orders','downtime_reasons',
   'status_events','downtime_events','memberships','roles','role_permissions',
   'support_access','audit_logs','oee_observations','production_entries',
   'operator_assignments','work_center_alternatives','work_center_capabilities',
   'daily_targets','user_permissions','production_transfers',
   'production_routing_steps','downtime_classification_corrections',
   'production_loss_profiles','production_loss_recovery_rates',
   'production_loss_actuals','production_loss_context_snapshots',
   'production_loss_estimates'];
begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved'
   then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
   if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
   perform private.require_permission(f,'factory','view');
   perform private.record_access(f,'READ');
   select to_jsonb(x) into fac from public.factories x where id=f;
   foreach tab in array tabs loop
     if query<>'' then query:=query||' union all ';end if;
     query:=query||format('select %L as table_name,coalesce(jsonb_agg(x),''[]'') as records
       from (select * from public.%I where factory_id=$1 %s limit 5000) x',
       tab,tab,case when tab in ('status_events','audit_logs','production_entries',
         'downtime_events') then 'order by created_at desc,id'
         when tab='production_loss_context_snapshots' then 'order by id desc'
         else '' end);
   end loop;
   query:=query||' union all select ''machine_statuses'',
     (select jsonb_agg(x) from public.machine_statuses x where code<>''maintenance'')
     union all select ''permissions'',(select jsonb_agg(x) from public.permissions x)';
   execute 'select jsonb_object_agg(table_name,records) from ('||query||') snapshot_tables'
     into data using f;
   foreach tab in array tabs loop
     if jsonb_array_length(data->tab)=5000 then limited:=array_append(limited,tab);end if;
   end loop;
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),
   'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,
   'factory',fac,'membership',m,
   'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,
   'tables',data,'supportFactories',
   (select coalesce(jsonb_agg(x),'[]'::jsonb) from public.support_access x
     where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end;
$$;
create function pg_temp.assert_snapshot_equivalent(f uuid default null)
returns void language plpgsql security invoker as $$
declare old jsonb; current jsonb; tab text; a jsonb; b jsonb;
 moved text[]:=array['audit_logs','downtime_classification_corrections',
   'production_loss_actuals','production_loss_context_snapshots','production_loss_estimates'];
begin
 old:=pg_temp.snapshot_previous(f);current:=public.factory_snapshot(f);
 old:=jsonb_set(old,'{tables}',(old->'tables')-moved);
 old:=jsonb_set(old,'{truncatedTables}',coalesce((select jsonb_agg(v)
   from jsonb_array_elements_text(old->'truncatedTables')v where not(v=any(moved))),'[]'));
 if (old-'tables') is distinct from (current-'tables') then
   raise exception 'snapshot metadata, permissions or truncation changed';
 end if;
 if (select array_agg(key order by key) from jsonb_each(old->'tables'))
   is distinct from (select array_agg(key order by key) from jsonb_each(current->'tables')) then
   raise exception 'snapshot section keys changed';
 end if;
 for tab,a in select key,value from jsonb_each(old->'tables') loop
   b:=current->'tables'->tab;
   if jsonb_array_length(a) is distinct from jsonb_array_length(b) then
     raise exception '% count changed',tab;
   end if;
   -- Existing ordered histories compare byte-for-byte as JSONB arrays.
   -- Other sections have no SQL order contract: compare every field and ID.
   if tab not in ('status_events','audit_logs','production_entries',
     'downtime_events','production_loss_context_snapshots') then
     select coalesce(jsonb_agg(v order by v::text),'[]') into a from jsonb_array_elements(a)v;
     select coalesce(jsonb_agg(v order by v::text),'[]') into b from jsonb_array_elements(b)v;
   end if;
   if a is distinct from b then raise exception '% content/order changed',tab;end if;
 end loop;
end;
$$;
do $verify$
declare person record; actor uuid; f uuid; foreign_factory uuid; seen int:=0;
begin
 -- Existing approved users include full and limited per-person access.
 for person in select m.user_id,m.factory_id from public.memberships m
   where m.status='approved'
     and not exists(select 1 from private.platform_admins p where p.user_id=m.user_id and p.enabled)
     and not exists(select 1 from public.support_access a where a.user_id=m.user_id
       and (a.mode='permanent' or (a.mode='temporary' and a.expires_at>now())))
     and exists(select 1 from public.user_permissions p where p.user_id=m.user_id
       and p.factory_id=m.factory_id and p.module='factory' and p.action='view') loop
   perform set_config('request.jwt.claim.sub',person.user_id::text,true);
   execute 'set local role authenticated';
   perform pg_temp.assert_snapshot_equivalent();
   execute 'reset role';
   actor:=person.user_id;f:=person.factory_id;seen:=seen+1;
 end loop;
 if seen<2 then raise exception 'existing full/limited TESTING users required';end if;
 -- Approved member factory selection must ignore an unrelated factory argument.
 insert into public.factories(name) values('QA snapshot contract isolation')returning id into foreign_factory;
 perform set_config('request.jwt.claim.sub',actor::text,true);
 execute 'set local role authenticated';
 perform pg_temp.assert_snapshot_equivalent(foreign_factory);
 if (public.factory_snapshot(foreign_factory)->'factory'->>'id')::uuid is distinct from f then
   raise exception 'factory context changed';
 end if;
 execute 'reset role';
 -- No per-person factory:view means denial, irrespective of a retained role.
 delete from public.user_permissions where user_id=actor and factory_id=f and module='factory'and action='view';
 execute 'set local role authenticated';
 begin
   perform public.factory_snapshot(null);raise exception 'missing factory permission accepted';
 exception when insufficient_privilege then null;end;
 execute 'reset role';
 -- Pending/rejected and no-user states preserve empty/null-factory semantics.
 update public.memberships set status='pending'where user_id=actor;
 execute 'set local role authenticated';perform pg_temp.assert_snapshot_equivalent();execute 'reset role';
 update public.memberships set status='rejected'where user_id=actor;
 execute 'set local role authenticated';perform pg_temp.assert_snapshot_equivalent();execute 'reset role';
 perform set_config('request.jwt.claim.sub','',true);
 execute 'set local role authenticated';perform pg_temp.assert_snapshot_equivalent();execute 'reset role';
 if (select prosecdef or provolatile<>'v'from pg_proc where oid='public.factory_snapshot(uuid)'::regprocedure)then
   raise exception 'snapshot invoker/READ-audit volatility contract changed';
 end if;
end;
$verify$;
rollback;
