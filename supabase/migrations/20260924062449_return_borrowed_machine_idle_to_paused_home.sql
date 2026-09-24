-- Borrowing temporarily runs a machine that Pause auto-idled. Keep that
-- pause origin until the home line resumes or the machine is changed manually.
create or replace function private.forget_line_pause_auto_idle()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status is distinct from new.status
    and not (
     old.status='idle' and new.status='running'
     and exists (
      select 1 from public.production_transfers t
      where t.factory_id=new.factory_id and t.alternative_id=new.id
        and t.ended_at is null
     )
    ) then
  delete from private.line_pause_auto_idled where work_center_id=new.id;
 end if;
 return new;
end$$;

-- Returning to a paused home line releases a running borrowed machine to
-- Idle. Other physical states, and returns after Resume, are left alone.
create or replace function private.finish_transfer()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 returned_alternative uuid;
 home_line uuid;
 pause_origin timestamptz;
 had_pause_origin boolean;
begin
 if new.status='running' and old.status<>'running' then
  update public.production_transfers
  set original_returned_at=now(),ended_at=now()
  where factory_id=new.factory_id and original_id=new.id and ended_at is null
  returning alternative_id into returned_alternative;

  if returned_alternative is not null then
   -- Serialize with Resume so the decision uses the current home pause.
   select c.line_id into home_line
   from public.work_centers c
   join public.production_lines l on l.factory_id=c.factory_id and l.id=c.line_id
   where c.factory_id=new.factory_id and c.id=returned_alternative
     and l.paused_at is not null
   for update of l;

   if home_line is not null then
    select m.auto_idled_at into pause_origin
    from private.line_pause_auto_idled m
    where m.factory_id=new.factory_id and m.line_id=home_line
      and m.work_center_id=returned_alternative;
    had_pause_origin := found;

    update public.work_centers
    set status='idle',updated_at=now()
    where factory_id=new.factory_id and id=returned_alternative
      and status='running';
    if found then
     insert into public.status_events
       (factory_id,work_center_id,old_status,new_status,created_by)
     values (new.factory_id,returned_alternative,'running','idle',auth.uid());

     -- The status trigger clears markers for ordinary changes. Restore the
     -- original pause marker only for this transfer-return transition.
     if had_pause_origin then
      insert into private.line_pause_auto_idled
        (factory_id,line_id,work_center_id,auto_idled_at)
      values (new.factory_id,home_line,returned_alternative,pause_origin);
     end if;
    end if;
   end if;
  end if;
 end if;
 return new;
end$$;
