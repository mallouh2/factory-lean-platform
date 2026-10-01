-- Keep operational content intact; move audit and loss review history to lazy readers.
create or replace function public.factory_snapshot(factory uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;data jsonb:='{}';limited text[]:='{}';
 query text:='';
 tabs text[]:=array[
   'areas','work_center_categories','production_lines','work_centers',
   'products','production_requests','production_orders','downtime_reasons',
   'status_events','downtime_events','memberships','roles','role_permissions',
   'support_access','oee_observations','production_entries',
   'operator_assignments','work_center_alternatives','work_center_capabilities',
   'daily_targets','user_permissions','production_transfers',
   'production_routing_steps',
   'production_loss_profiles','production_loss_recovery_rates'];
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
     if query<>'' then query:=query||',';end if;
     query:=query||format('%L,(select coalesce(jsonb_agg(x),''[]'')
       from (select * from public.%I where factory_id=$1 %s limit 5000) x)',
       tab,tab,case when tab in ('status_events','audit_logs','production_entries',
         'downtime_events') then 'order by created_at desc,id'
         when tab='production_loss_context_snapshots' then 'order by id desc'
         else '' end);
   end loop;
   query:=query||', ''machine_statuses'',
     (select jsonb_agg(x) from public.machine_statuses x where code<>''maintenance'')
     , ''permissions'',(select jsonb_agg(x) from public.permissions x)';
   execute 'select jsonb_build_object('||query||')'
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

-- Authenticated, factory-scoped history readers. No table/write grants or RLS changes.
create function public.audit_history(factory uuid, search text default '', page integer default 1)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare total bigint; result jsonb; p integer:=greatest(1,coalesce(page,1));
begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'audit','view');
 if p>1000000 or length(coalesce(search,''))>2000 then
   raise exception 'invalid_history_query' using errcode='22023';end if;
 select count(*) into total from public.audit_logs a where a.factory_id=$1
   and (coalesce(search,'')='' or strpos(lower(to_jsonb(a)::text),lower(search))>0);
 select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id),'[]') into result
 from (select a.* from public.audit_logs a where a.factory_id=$1
   and (coalesce(search,'')='' or strpos(lower(to_jsonb(a)::text),lower(search))>0)
   order by a.created_at desc,a.id limit 50 offset (p-1)*50) x;
 return jsonb_build_object('rows',result,'total',total,'page',p,'pageSize',50,
   'pages',greatest(1,ceil(total/50.0)::integer));
end;
$$;
revoke all on function public.audit_history(uuid,text,integer) from public,anon;
grant execute on function public.audit_history(uuid,text,integer) to authenticated;

-- Whitelisted query kinds, never an arbitrary table name. Raw contexts stay on
-- the server and are read in bounded pages for the unchanged loss model.
create function public.production_loss_history(factory uuid, kind text default 'events',
 event uuid default null, page integer default 1)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare total bigint; result jsonb; selected public.downtime_events;
 p integer:=greatest(1,coalesce(page,1)); size integer;
begin
 perform private.require_permission(factory,'factory','view');
 perform private.require_permission(factory,'downtime','view');
 if p>1000000 then raise exception 'invalid_history_query' using errcode='22023';end if;
 if kind='events' then
   size:=30;
   select count(*) into total from public.downtime_events d
     where d.factory_id=$1 and d.ended_at is not null;
   select coalesce(jsonb_agg(to_jsonb(x) order by x.ended_at desc,x.id),'[]') into result
   from (select d.* from public.downtime_events d
     where d.factory_id=$1 and d.ended_at is not null
     order by d.ended_at desc,d.id limit size offset (p-1)*size) x;
 else
   select d.* into selected from public.downtime_events d
     where d.factory_id=$1 and d.id=$3 and d.ended_at is not null;
   if not found then raise exception 'history_event_not_found' using errcode='P0002';end if;
   if kind='detail' then
     return jsonb_build_object('event',to_jsonb(selected),
       'actual',(select to_jsonb(a) from public.production_loss_actuals a
         where a.factory_id=$1 and a.event_id=$3),
       'saved',(select to_jsonb(e) from public.production_loss_estimates e
         where e.factory_id=$1 and e.event_id=$3),
       'correction',(select to_jsonb(c) from public.downtime_classification_corrections c
         where c.factory_id=$1 and c.event_id=$3 order by c.corrected_at desc,c.id desc limit 1));
   elsif kind='contexts' then
     size:=50;
     select count(*) into total from public.production_loss_context_snapshots c
       where c.factory_id=$1 and c.event_id=$3;
     select coalesce(jsonb_agg(to_jsonb(x) order by x.captured_at,x.id),'[]') into result
     from (select c.* from public.production_loss_context_snapshots c
       where c.factory_id=$1 and c.event_id=$3
       order by c.captured_at,c.id limit size offset (p-1)*size) x;
   elsif kind='observations' then
     -- The model/suggestion comparators both require the same work center.
     -- Do not limit to the displayed event page or to an arbitrary recent cap.
     size:=50;
     select count(*) into total from public.downtime_events d
       join public.production_loss_actuals a on a.factory_id=d.factory_id and a.event_id=d.id
       where d.factory_id=$1 and d.ended_at is not null and d.id<>$3
         and d.work_center_id=selected.work_center_id;
     select coalesce(jsonb_agg(x.record order by x.ended_at desc,x.id),'[]') into result
     from (select d.id,d.ended_at,jsonb_build_object('event',to_jsonb(d),'actual',to_jsonb(a),
       'saved',(select to_jsonb(e) from public.production_loss_estimates e
         where e.factory_id=$1 and e.event_id=d.id),
       'correction',(select to_jsonb(c) from public.downtime_classification_corrections c
         where c.factory_id=$1 and c.event_id=d.id order by c.corrected_at desc,c.id desc limit 1)) record
       from public.downtime_events d join public.production_loss_actuals a
         on a.factory_id=d.factory_id and a.event_id=d.id
       where d.factory_id=$1 and d.ended_at is not null and d.id<>$3
         and d.work_center_id=selected.work_center_id
       order by d.ended_at desc,d.id limit size offset (p-1)*size) x;
   else raise exception 'invalid_history_query' using errcode='22023';
   end if;
 end if;
 return jsonb_build_object('rows',result,'total',total,'page',p,'pageSize',size,
   'pages',greatest(1,ceil(total/size::numeric)::integer));
end;
$$;
revoke all on function public.production_loss_history(uuid,text,uuid,integer) from public,anon;
grant execute on function public.production_loss_history(uuid,text,uuid,integer) to authenticated;
