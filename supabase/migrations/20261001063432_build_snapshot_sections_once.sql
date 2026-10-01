-- Build the same 32 sections directly, avoiding a UNION intermediate and
-- re-aggregation of the large audit/loss JSON values. Keep each bounded table
-- query and its ordering intact. SECURITY INVOKER and all access checks persist.
-- VOLATILE is intentional: platform/support reads still record access.
create or replace function public.factory_snapshot(factory uuid default null)
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
