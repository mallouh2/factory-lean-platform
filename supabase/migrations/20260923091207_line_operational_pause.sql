-- A line pause is an operational decision, independent of machine status and downtime.
alter table public.production_lines
 add column paused_at timestamptz,
 add column pause_reason text,
 add constraint production_lines_pause_reason_check check (
  (paused_at is null and pause_reason is null) or
  (paused_at is not null and pause_reason in
   ('borrow_machine','planned_stop','cleaning','changeover','no_production','other'))
 );

create function private.set_line_pause(f uuid,l uuid,paused boolean,reason text)
returns void language plpgsql security definer set search_path='' as $$
begin
 perform private.require_permission(f,'centers','edit');
 if paused is null or (paused and reason not in
   ('borrow_machine','planned_stop','cleaning','changeover','no_production','other')) then
  raise exception 'invalid_pause_reason';
 end if;
 update public.production_lines
 set paused_at=case when paused then coalesce(paused_at,now()) else null end,
     pause_reason=case when paused then reason else null end
 where id=l and factory_id=f and not archived;
 if not found then raise exception 'not_found'; end if;
end$$;

create function public.set_line_pause(factory uuid,line uuid,paused boolean,reason text default null)
returns void language sql security invoker set search_path='' as $$
 select private.set_line_pause(factory,line,paused,reason)
$$;

revoke all on function private.set_line_pause(uuid,uuid,boolean,text),
 public.set_line_pause(uuid,uuid,boolean,text) from public,anon;
grant execute on function private.set_line_pause(uuid,uuid,boolean,text),
 public.set_line_pause(uuid,uuid,boolean,text) to authenticated;
