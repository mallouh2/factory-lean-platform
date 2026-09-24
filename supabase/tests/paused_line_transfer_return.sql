-- Focused TESTING check. The fixture is rolled back on success.
do $$
declare
 f uuid; actor uuid; cat uuid; home uuid; borrowing uuid;
 alt uuid; original uuid; product_id uuid; order_id uuid; reason_id uuid;
 transfer_id uuid; physical_status text;
 tag text := substr(replace(gen_random_uuid()::text,'-',''),1,10);
begin
 select factory_id,user_id into f,actor from public.memberships
 where is_owner and status='approved' order by created_at limit 1;
 select id into cat from public.work_center_categories
 where factory_id=f and not archived limit 1;
 if f is null or cat is null then raise exception 'missing_testing_owner_or_category'; end if;

 begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.production_lines(factory_id,name,code)
  values(f,'Return home '||tag,'RH-'||tag) returning id into home;
  insert into public.production_lines(factory_id,name,code)
  values(f,'Return borrower '||tag,'RB-'||tag) returning id into borrowing;
  insert into public.products(factory_id,name,code)
  values(f,'Return product '||tag,'RP-'||tag) returning id into product_id;
  insert into public.production_orders(factory_id,product_id,line_id,code,status,target_quantity)
  values(f,product_id,borrowing,'RO-'||tag,'active',100) returning id into order_id;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status)
  values(f,home,cat,'Returned alternative','RA-'||tag,'running') returning id into alt;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,borrowing,cat,'Return original','RR-'||tag,'stopped',order_id)
  returning id into original;
  insert into public.downtime_reasons(factory_id,name)
  values(f,'Return failure '||tag) returning id into reason_id;
  insert into public.downtime_events(factory_id,work_center_id,reason_id)
  values(f,original,reason_id);
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,original,alt);

  -- An auto-idled machine keeps its pause origin while running on the borrower.
  perform public.set_line_pause(f,home,true,'borrow_machine');
  if (select status from public.work_centers where id=alt)<>'idle'
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
  then raise exception 'pause_origin_missing'; end if;
  transfer_id := public.transfer_production(f,original,alt,'Return test');
  if (select status from public.work_centers where id=alt)<>'running'
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
  then raise exception 'borrow_lost_pause_origin_or_assignment'; end if;

  perform public.change_status(f,original,'running');
  if not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
    or (select status from public.work_centers where id=alt)<>'idle'
    or (select line_id from public.work_centers where id=alt)<>home
    or not exists(select 1 from public.production_lines where id=home and paused_at is not null)
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
    or not exists(select 1 from public.status_events
                  where work_center_id=alt and old_status='running' and new_status='idle')
  then raise exception 'paused_home_return_failed'; end if;

  perform public.set_line_pause(f,home,false,null);
  if (select status from public.work_centers where id=alt)<>'running'
    or exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
  then raise exception 'later_resume_failed'; end if;

  -- Resume before closure must leave the borrowed machine running on return.
  perform public.change_status(f,original,'stopped',reason_id);
  perform public.set_line_pause(f,home,true,'borrow_machine');
  transfer_id := public.transfer_production(f,original,alt,'Resume before return');
  perform public.set_line_pause(f,home,false,null);
  perform public.change_status(f,original,'running');
  if (select status from public.work_centers where id=alt)<>'running'
    or (select line_id from public.work_centers where id=alt)<>home
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
  then raise exception 'resumed_home_return_changed_status'; end if;

  -- A real non-running physical state must survive transfer closure.
  foreach physical_status in array array['stopped','setup','offline'] loop
   perform public.change_status(f,alt,'idle');
   perform public.change_status(f,original,'stopped',reason_id);
   perform public.set_line_pause(f,home,true,'borrow_machine');
   transfer_id := public.transfer_production(f,original,alt,'Non-running return');
   perform public.change_status(f,alt,physical_status,reason_id);
   perform public.change_status(f,original,'running');
   if (select status from public.work_centers where id=alt)<>physical_status
     or (select line_id from public.work_centers where id=alt)<>home
     or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
   then raise exception 'non_running_return_overwritten: %',physical_status; end if;
   perform public.set_line_pause(f,home,false,null);
  end loop;

  raise exception '__rollback_return_fixture__';
 exception when raise_exception then
  if sqlerrm <> '__rollback_return_fixture__' then raise; end if;
 end;
end$$;
