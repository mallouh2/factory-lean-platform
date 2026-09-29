-- The V1 backfill copied the latest mutable legacy notes. Reconcile only
-- pre-V1 rows against each event's original INSERT audit, which records the
-- actual initial reason, note, actor, and event creation time.
begin;

alter table public.downtime_events disable trigger guard_downtime_capture;

create temp table downtime_v1_originals on commit drop as
select d.id,
  a.id as audit_id,
  (a.new_data->>'reason_id')::uuid as original_reason,
  (a.new_data->>'sub_reason_id')::uuid as original_sub_reason,
  coalesce(a.new_data->>'notes','') as original_note,
  (a.new_data->>'created_by')::uuid as original_actor,
  (a.new_data->>'created_at')::timestamptz as original_time
from public.downtime_events d
left join lateral (
  select a.id,a.new_data from public.audit_logs a
  where a.entity='downtime_events' and a.action='INSERT'
    and a.entity_id=d.id
  order by a.created_at,a.id limit 1
) a on true
where d.reason_id is not null and d.initial_entered_at=d.created_at;

do $$
begin
  if exists(select 1 from downtime_v1_originals
    where audit_id is null or original_reason is null or original_time is null) then
    raise exception 'legacy_downtime_audit_missing';
  end if;
end;
$$;

update public.downtime_events d set
  reason_id=o.original_reason,
  sub_reason_id=o.original_sub_reason,
  initial_note=o.original_note,
  initial_entered_by=o.original_actor,
  initial_entered_at=o.original_time
from downtime_v1_originals o
where d.id=o.id and
  (d.reason_id,d.sub_reason_id,d.initial_note,d.initial_entered_by,d.initial_entered_at)
    is distinct from
  (o.original_reason,o.original_sub_reason,o.original_note,o.original_actor,o.original_time);

alter table public.downtime_events enable trigger guard_downtime_capture;
commit;
