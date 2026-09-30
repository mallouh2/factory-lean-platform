-- An engineer records a completed, ready V1 estimate once. Later actuals and
-- later configuration never rewrite the accepted estimate or its assumptions.
create table public.production_loss_estimates (
  id uuid primary key default gen_random_uuid(),
  factory_id uuid not null references public.factories(id),
  event_id uuid not null,
  model_version integer not null check(model_version=1),
  result jsonb not null,
  calculated_at timestamptz not null default clock_timestamp(),
  recorded_by uuid not null references auth.users(id),
  unique(factory_id,event_id),
  foreign key(factory_id,event_id) references public.downtime_events(factory_id,id),
  check(jsonb_typeof(result)='object')
);
alter table public.production_loss_estimates enable row level security;
create policy read_authorized on public.production_loss_estimates
  for select to authenticated
  using(private.has_permission(factory_id,'downtime','view'));
grant select on public.production_loss_estimates to authenticated;
create trigger audit_record after insert on public.production_loss_estimates
  for each row execute function private.audit_change();

create function public.save_production_loss_estimate(
  factory uuid,event uuid,estimate jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare saved_id uuid; stamp timestamptz;
begin
  perform private.require_permission(factory,'downtime','edit');
  if not exists(select 1 from public.downtime_events
    where factory_id=factory and id=event and ended_at is not null
      and loss_model_version=1) then raise exception 'downtime_not_reviewable'; end if;
  if jsonb_typeof(estimate) is distinct from 'object'
    or estimate->>'readiness' is distinct from 'READY'
    or estimate->>'model_version' is distinct from '1'
    or jsonb_typeof(estimate->'assumptions') is distinct from 'array'
    or jsonb_typeof(estimate->'missing') is distinct from 'array' then
    raise exception 'loss_estimate_incomplete'; end if;
  if jsonb_array_length(estimate->'assumptions')=0
    or jsonb_array_length(estimate->'missing')<>0 then
    raise exception 'loss_estimate_incomplete'; end if;
  if exists(select 1 from jsonb_array_elements(estimate->'assumptions') a
    where not exists(select 1 from public.production_loss_context_snapshots s
      where s.factory_id=factory and s.event_id=event
        and s.id=(a->>'context_snapshot_id')::bigint)) then
    raise exception 'loss_estimate_context_mismatch'; end if;
  stamp:=clock_timestamp();
  insert into public.production_loss_estimates
    (factory_id,event_id,model_version,result,calculated_at,recorded_by)
  values(factory,event,1,
    jsonb_set(estimate - 'actual_scrap_quantity' - 'actual_recovery_minutes',
      '{calculated_at}',to_jsonb(stamp)),stamp,auth.uid())
  on conflict(factory_id,event_id) do nothing
  returning id into saved_id;
  if saved_id is null then raise exception 'loss_estimate_locked'; end if;
  return saved_id;
end;
$$;
revoke all on function public.save_production_loss_estimate(uuid,uuid,jsonb)
  from public,anon,authenticated;
grant execute on function public.save_production_loss_estimate(uuid,uuid,jsonb)
  to authenticated;

create or replace function public.factory_snapshot(factory uuid default null)
returns jsonb language plpgsql security invoker set search_path='' as $$
declare m jsonb;f uuid;fac jsonb;tab text;rows jsonb;data jsonb:='{}';limited text[]:='{}';
begin
 select to_jsonb(x) into m from public.memberships x where user_id=auth.uid();
 f:=case when private.is_platform_admin() then $1 when m->>'status'='approved'
   then (m->>'factory_id')::uuid else $1 end;
 if f is not null then
   if private.is_platform_admin() then perform private.open_platform_factory(f);end if;
   perform private.require_permission(f,'factory','view');
   perform private.record_access(f,'READ');
   select to_jsonb(x) into fac from public.factories x where id=f;
   foreach tab in array array[
     'areas','work_center_categories','production_lines','work_centers',
     'products','production_requests','production_orders','downtime_reasons',
     'status_events','downtime_events','memberships','roles','role_permissions',
     'support_access','audit_logs','oee_observations','production_entries',
     'operator_assignments','work_center_alternatives','work_center_capabilities',
     'daily_targets','user_permissions','production_transfers',
     'production_routing_steps','downtime_classification_corrections',
     'production_loss_profiles','production_loss_recovery_rates',
     'production_loss_actuals','production_loss_context_snapshots',
     'production_loss_estimates'] loop
     execute format('select coalesce(jsonb_agg(x),''[]'') from
       (select * from public.%I where factory_id=$1 %s limit 5000) x',
       tab,case when tab in ('status_events','audit_logs','production_entries',
         'downtime_events') then 'order by created_at desc,id'
         when tab='production_loss_context_snapshots' then 'order by id desc'
         else '' end) into rows using f;
     data:=data||jsonb_build_object(tab,rows);
     if jsonb_array_length(rows)=5000 then limited:=array_append(limited,tab);end if;
   end loop;
   data:=data||jsonb_build_object('machine_statuses',
     (select jsonb_agg(x) from public.machine_statuses x where code<>'maintenance'),
     'permissions',(select jsonb_agg(x) from public.permissions x));
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
