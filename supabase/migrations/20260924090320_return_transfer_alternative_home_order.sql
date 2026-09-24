-- A transfer temporarily assigns the alternative to the borrowing order.
-- Keep its previous assignment so the approved original->Running path can
-- release it to its home line in the same transaction.
alter table public.production_transfers
 add column alternative_previous_order_id uuid,
 add column alternative_order_captured boolean not null default false,
 add foreign key (factory_id,alternative_previous_order_id)
   references public.production_orders(factory_id,id);

-- This development database can contain an open transfer created before the
-- assignment was recorded. Recover only an unambiguous active home order.
with home_orders as (
 select t.id, min(o.id::text)::uuid as home_order_id
 from public.production_transfers t
 join public.work_centers a on a.factory_id=t.factory_id and a.id=t.alternative_id
 join public.production_orders o on o.factory_id=t.factory_id
   and o.line_id=a.line_id and o.status='active' and o.id<>t.order_id
 where t.ended_at is null and a.order_id=t.order_id
 group by t.id
 having count(*)=1
)
update public.production_transfers t
set alternative_previous_order_id=h.home_order_id,
    alternative_order_captured=true
from home_orders h where t.id=h.id;

create or replace function private.transfer_production(f uuid,w uuid,a uuid,n text)
returns uuid language plpgsql security definer set search_path='' as $$
declare o uuid;d uuid;i uuid;previous_order uuid;
begin
 perform private.require_permission(f,'centers','edit');
 perform private.require_permission(f,'orders','edit');
 perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform 1 from public.work_centers where factory_id=f and id in (w,a) order by id for update;
 select order_id into o from public.work_centers
 where id=w and factory_id=f and not archived and status='stopped';
 select id into d from public.downtime_events
 where work_center_id=w and factory_id=f and ended_at is null;
 if o is null or d is null or not exists(
  select 1 from public.production_orders where id=o and status='active'
 ) then raise exception 'invalid_order'; end if;
 if not exists(
   select 1 from public.work_center_alternatives
   where factory_id=f and work_center_id=w and alternative_id=a
 ) or not exists(
   select 1 from public.work_centers c
   left join public.production_lines home
     on home.id=c.line_id and home.factory_id=f and not home.archived
   where c.id=a and c.factory_id=f and not c.archived and c.status='idle'
     and (c.order_id is null or c.order_id=o or home.paused_at is not null)
 ) or (select category_id from public.work_centers where id=w)
      is distinct from (select category_id from public.work_centers where id=a)
   or exists(
     select 1 from public.production_transfers
     where factory_id=f and alternative_id=a and ended_at is null
   )
 then raise exception 'incompatible_alternative'; end if;
 select order_id into previous_order
 from public.work_centers where id=a and factory_id=f;
 insert into public.production_transfers(
  factory_id,original_id,alternative_id,order_id,downtime_id,reason,
  created_by,alternative_previous_order_id,alternative_order_captured
 ) values(f,w,a,o,d,n,auth.uid(),previous_order,true) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;
end$$;

create or replace function private.finish_transfer()
returns trigger language plpgsql security definer set search_path='' as $$
declare
 returned_alternative uuid;
 borrowed_order uuid;
 previous_order uuid;
 order_captured boolean;
 home_line uuid;
 pause_origin timestamptz;
 had_pause_origin boolean;
begin
 if new.status='running' and old.status<>'running' then
  update public.production_transfers
  set original_returned_at=now(),ended_at=now()
  where factory_id=new.factory_id and original_id=new.id and ended_at is null
  returning alternative_id,order_id,alternative_previous_order_id,
            alternative_order_captured
  into returned_alternative,borrowed_order,previous_order,order_captured;

  if returned_alternative is not null then
   -- Do not overwrite an assignment changed after borrowing began.
   if order_captured then
    update public.work_centers
    set order_id=previous_order,updated_at=now()
    where factory_id=new.factory_id and id=returned_alternative
      and order_id=borrowed_order
      and order_id is distinct from previous_order;
   end if;

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
