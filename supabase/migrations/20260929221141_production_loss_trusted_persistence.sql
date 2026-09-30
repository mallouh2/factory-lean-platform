-- Browser sessions may preview V1 estimates, but can no longer submit result
-- JSON to PostgreSQL. Only the trusted calculation service can persist one.
revoke execute on function public.save_production_loss_estimate(uuid,uuid,jsonb)
  from authenticated;

create function public.persist_production_loss_estimate(
  factory uuid,event uuid,actor uuid,estimate jsonb,correction uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare saved_id uuid; stamp timestamptz; current_correction uuid;
begin
  -- EXECUTE is granted only to service_role. The authenticated actor comes
  -- from the verified user JWT in the trusted calculation service.
  if not exists(select 1 from public.user_permissions p
    where p.factory_id=factory and p.user_id=actor
      and p.module='downtime' and p.action='edit'
      and (exists(select 1 from public.memberships m
        where m.factory_id=factory and m.user_id=actor
          and m.status='approved')
        or exists(select 1 from public.support_access s
          where s.factory_id=factory and s.user_id=actor
            and (s.mode='permanent' or
              (s.mode='temporary' and s.expires_at>now())))))
    and not exists(select 1 from private.platform_admins a
      join private.platform_scopes s on s.user_id=a.user_id
      where a.user_id=actor and a.enabled and s.factory_id=factory
        and s.expires_at>now()) then
    raise exception 'permission_denied' using errcode='42501';
  end if;
  if not exists(select 1 from public.downtime_events d
    where d.factory_id=factory and d.id=event and d.ended_at is not null
      and d.loss_model_version=1) then
    raise exception 'downtime_not_reviewable';
  end if;
  select c.id into current_correction
    from public.downtime_classification_corrections c
    where c.factory_id=factory and c.event_id=event
    order by c.corrected_at desc,c.id desc limit 1;
  if current_correction is distinct from correction then
    raise exception 'loss_estimate_context_mismatch';
  end if;
  if jsonb_typeof(estimate) is distinct from 'object'
    or estimate->>'readiness' is distinct from 'READY'
    or estimate->>'model_version' is distinct from '1'
    or jsonb_typeof(estimate->'assumptions') is distinct from 'array'
    or jsonb_typeof(estimate->'missing') is distinct from 'array'
    or jsonb_array_length(estimate->'assumptions')=0
    or jsonb_array_length(estimate->'missing')<>0 then
    raise exception 'loss_estimate_incomplete';
  end if;
  if exists(select 1 from jsonb_array_elements(estimate->'assumptions') a
    where not exists(select 1 from public.production_loss_context_snapshots s
      where s.factory_id=factory and s.event_id=event
        and s.id=(a->>'context_snapshot_id')::bigint)) then
    raise exception 'loss_estimate_context_mismatch';
  end if;
  stamp:=clock_timestamp();
  -- The service already validated this actor. Give the existing audit trigger
  -- the human actor rather than leaving a service account/null identity.
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.production_loss_estimates
    (factory_id,event_id,model_version,result,calculated_at,recorded_by)
  values(factory,event,1,
    jsonb_set(estimate - 'actual_scrap_quantity' - 'actual_recovery_minutes',
      '{calculated_at}',to_jsonb(stamp)),stamp,actor)
  on conflict(factory_id,event_id) do nothing
  returning id into saved_id;
  if saved_id is null then raise exception 'loss_estimate_locked'; end if;
  return saved_id;
end;
$$;
revoke all on function public.persist_production_loss_estimate(
  uuid,uuid,uuid,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.persist_production_loss_estimate(
  uuid,uuid,uuid,jsonb,uuid) to service_role;
