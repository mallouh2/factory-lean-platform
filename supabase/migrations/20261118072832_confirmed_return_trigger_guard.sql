-- All original-machine status writers must use the confirmed return command.
CREATE OR REPLACE FUNCTION private.finish_transfer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if exists(select 1 from public.production_transfers t where t.factory_id=new.factory_id and t.original_id=new.id and t.ended_at is null and not private.execution_command_allowed(new.factory_id,t.order_id,array['RETURN_PRODUCTION']))then raise exception 'f48UseReturn'using errcode='22023';end if;
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
end$function$;
