-- Renew only the explicitly selected factory during an authenticated platform snapshot.
-- Each renewal and application read is audited; ordinary user authorization is unchanged.
create or replace function public.factory_snapshot(factory uuid default null) returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved' then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
 if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
 perform private.require_permission(f,'factory','view');
 perform private.record_access(f,'READ');
 select to_jsonb(x) into fac from public.factories x where id=f;
 foreach tab in array array['areas','production_lines','work_centers','products','production_orders','downtime_reasons','status_events','downtime_events','memberships','roles','role_permissions','support_access','audit_logs','oee_observations','production_entries','operator_assignments','work_center_alternatives','work_center_capabilities','daily_targets','user_permissions','production_transfers','production_routing_steps'] loop
 execute format('select coalesce(jsonb_agg(x),''[]'') from (select * from public.%I where factory_id=$1 %s limit 5000) x',tab,case when tab in ('status_events','audit_logs','production_entries','downtime_events') then 'order by created_at desc,id' else '' end) into rows using f;
 data:=data||jsonb_build_object(tab,rows);
 if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
 end loop;
 data:=data||jsonb_build_object('machine_statuses',(select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),'permissions',(select jsonb_agg(x) from public.permissions x));
 end if;
 return jsonb_build_object('platformAdmin',private.is_platform_admin(),'factories',case when f is null then private.platform_factories() else '[]'::jsonb end,'factory',fac,'membership',m,'permissions',case when f is null then '{}'::text[] else public.access_matrix(f) end,'tables',data,'supportFactories',(select coalesce(jsonb_agg(x),'[]') from public.support_access x where user_id=auth.uid()),'truncatedTables',limited,'fetchedAt',now());
end$$;

