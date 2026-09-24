-- A pause records exactly the running machines it moved to idle.
-- The record lives outside the Data API and is cleared by any later status change.
create table private.line_pause_auto_idled (
 factory_id uuid not null,
 line_id uuid not null,
 work_center_id uuid primary key,
 auto_idled_at timestamptz not null default now(),
 foreign key (factory_id,line_id) references public.production_lines(factory_id,id),
 foreign key (factory_id,work_center_id) references public.work_centers(factory_id,id)
);
alter table private.line_pause_auto_idled enable row level security;
revoke all on private.line_pause_auto_idled from public,anon,authenticated;

create function private.forget_line_pause_auto_idle()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if old.status is distinct from new.status then
  delete from private.line_pause_auto_idled where work_center_id=new.id;
 end if;
 return new;
end$$;
revoke all on function private.forget_line_pause_auto_idle() from public,anon,authenticated;
create trigger forget_line_pause_auto_idle
after update of status on public.work_centers
for each row execute function private.forget_line_pause_auto_idle();

create or replace function private.set_line_pause(f uuid,l uuid,paused boolean,reason text)
returns void language plpgsql security definer set search_path='' as $$
declare idled_ids uuid[]; restored_ids uuid[];
begin
 perform private.require_permission(f,'centers','edit');
 if paused is null or (paused and reason not in
   ('borrow_machine','planned_stop','cleaning','changeover','no_production','other')) then
  raise exception 'invalid_pause_reason';
 end if;
 perform 1 from public.production_lines
 where id=l and factory_id=f and not archived for update;
 if not found then raise exception 'not_found'; end if;

 if paused then
  update public.production_lines
  set paused_at=coalesce(paused_at,now()),pause_reason=reason
  where id=l;

  -- An already borrowed machine belongs to its open transfer, not this line's
  -- physical pause. All other running home machines become available idle.
  with idled as (
   update public.work_centers c
   set status='idle',updated_at=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='running'
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
   )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into idled_ids from idled;

  -- Run this after the UPDATE's status triggers, which clear old markers.
  insert into private.line_pause_auto_idled(factory_id,line_id,work_center_id)
  select f,l,id from unnest(idled_ids) id;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'running','idle',auth.uid() from unnest(idled_ids) id;
 else
  update public.production_lines
  set paused_at=null,pause_reason=null
  where id=l;

  -- Lock centers before reading their markers. A concurrent manual status
  -- change either finishes first and removes its marker, or follows Resume.
  perform 1 from public.work_centers c
  where c.factory_id=f and c.line_id=l
    and exists (
     select 1 from private.line_pause_auto_idled m
     where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
    )
  order by c.id for update;

  with restored as (
   update public.work_centers c
   set status='running',updated_at=now(),last_restart_time=now()
   where c.factory_id=f and c.line_id=l and not c.archived and c.status='idle'
     and exists (
      select 1 from private.line_pause_auto_idled m
      where m.factory_id=f and m.line_id=l and m.work_center_id=c.id
     )
     and not exists (
      select 1 from public.production_transfers t
      where t.factory_id=f and t.alternative_id=c.id and t.ended_at is null
     )
   returning c.id
  )
  select coalesce(array_agg(id),'{}'::uuid[]) into restored_ids from restored;
  insert into public.status_events(factory_id,work_center_id,old_status,new_status,created_by)
  select f,id,'idle','running',auth.uid() from unnest(restored_ids) id;

  -- A pause is finished even if a machine was borrowed or manually changed.
  delete from private.line_pause_auto_idled where factory_id=f and line_id=l;
 end if;
end$$;
