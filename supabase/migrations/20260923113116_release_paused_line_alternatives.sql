-- A paused home line releases an idle alternative from its old order context.
-- All other transfer requirements, including the explicit relationship and
-- same category, continue to apply.
create or replace function private.transfer_production(f uuid,w uuid,a uuid,n text)
returns uuid language plpgsql security definer set search_path='' as $$
declare o uuid;d uuid;i uuid;
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
 insert into public.production_transfers(
  factory_id,original_id,alternative_id,order_id,downtime_id,reason,created_by
 ) values(f,w,a,o,d,n,auth.uid()) returning id into i;
 update public.work_centers set order_id=o where id=a;
 perform private.change_status(f,a,'running',null,null,n,null,null,null,false);
 update public.downtime_events set alternative_id=a,transferred=true where id=d;
 return i;
end$$;
