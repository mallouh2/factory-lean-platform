-- Use the positional argument in the UPDATE expression: downtime_events has
-- its own notes column, which otherwise makes the parameter ambiguous.
create or replace function public.approve_planned_downtime(factory uuid,event uuid,
  notes text default '')
returns uuid language plpgsql security definer set search_path='' as $$
begin
  perform private.require_permission(factory,'downtime','edit');
  if length(coalesce($3,''))>2000 then raise exception 'invalid_notes'; end if;
  update public.downtime_events set approved_by=auth.uid(),
    approved_at=clock_timestamp(),engineering_note=coalesce($3,'')
    where factory_id=factory and id=event and stop_nature='planned'
      and ended_at is not null and approved_at is null;
  if not found then raise exception 'downtime_not_reviewable'; end if;
  return event;
end;
$$;
