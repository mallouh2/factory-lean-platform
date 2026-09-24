-- Focused TESTING check. The exception block rolls all fixture changes back.
do $$
declare
 f uuid; actor uuid; cat uuid; reason_id uuid; home uuid; borrowing uuid;
 m1 uuid; m2 uuid; stopped uuid; idle_before uuid; original uuid;
 product_id uuid; order_id uuid; downtime_id uuid; transfer_id uuid;
 tag text := substr(replace(gen_random_uuid()::text,'-',''),1,10);
begin
 select m.factory_id,m.user_id into f,actor
 from public.memberships m
 where m.is_owner and m.status='approved'
 order by m.created_at limit 1;
 if f is null then raise exception 'no_testing_owner'; end if;
 select id into cat from public.work_center_categories
 where factory_id=f and not archived limit 1;
 if cat is null then raise exception 'no_testing_category'; end if;

 begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.production_lines(factory_id,name,code)
  values(f,'Pause home '||tag,'PH-'||tag) returning id into home;
  insert into public.production_lines(factory_id,name,code)
  values(f,'Borrowing line '||tag,'PB-'||tag) returning id into borrowing;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,position)
  values(f,home,cat,'Running one','P1-'||tag,'running',0) returning id into m1;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,position)
  values(f,home,cat,'Running two','P2-'||tag,'running',1) returning id into m2;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,position)
  values(f,home,cat,'Stopped','P3-'||tag,'stopped',2) returning id into stopped;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,position)
  values(f,home,cat,'Idle before pause','P4-'||tag,'idle',3) returning id into idle_before;

  -- Running + running + stopped, with a pre-existing idle machine.
  perform public.set_line_pause(f,home,true,'planned_stop');
  if (select count(*) from public.work_centers where id in (m1,m2) and status='idle')<>2
    or (select status from public.work_centers where id=stopped)<>'stopped'
    or (select status from public.work_centers where id=idle_before)<>'idle'
    or (select count(*) from private.line_pause_auto_idled where line_id=home)<>2
  then raise exception 'pause_running_only_failed: %, %, %, %, markers %',
    (select status from public.work_centers where id=m1),
    (select status from public.work_centers where id=m2),
    (select status from public.work_centers where id=stopped),
    (select status from public.work_centers where id=idle_before),
    (select count(*) from private.line_pause_auto_idled where line_id=home);
  end if;
  perform public.set_line_pause(f,home,false,null);
  if (select count(*) from public.work_centers where id in (m1,m2) and status='running')<>2
    or (select status from public.work_centers where id=stopped)<>'stopped'
    or (select status from public.work_centers where id=idle_before)<>'idle'
    or exists(select 1 from private.line_pause_auto_idled where line_id=home)
    or (select count(*) from public.status_events
        where work_center_id in (m1,m2) and old_status='running' and new_status='idle')<>2
    or (select count(*) from public.status_events
        where work_center_id in (m1,m2) and old_status='idle' and new_status='running')<>2
  then raise exception 'resume_auto_idled_only_failed'; end if;

  -- Running + idle + stopped. The pre-existing idle stays idle.
  update public.work_centers set status='idle' where id=m2;
  perform public.set_line_pause(f,home,true,'borrow_machine');
  if (select status from public.work_centers where id=m1)<>'idle'
    or (select status from public.work_centers where id=m2)<>'idle'
    or (select status from public.work_centers where id=stopped)<>'stopped'
    or (select count(*) from private.line_pause_auto_idled where line_id=home)<>1
  then raise exception 'preexisting_idle_pause_failed'; end if;

  -- Borrow an auto-idled home machine through a real open transfer.
  insert into public.products(factory_id,name,code)
  values(f,'Pause test product','PP-'||tag) returning id into product_id;
  insert into public.production_orders(factory_id,product_id,line_id,code,status,target_quantity)
  values(f,product_id,borrowing,'PO-'||tag,'active',100) returning id into order_id;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,borrowing,cat,'Stopped original','POC-'||tag,'stopped',order_id)
  returning id into original;
  insert into public.downtime_reasons(factory_id,name)
  values(f,'Pause test failure '||tag) returning id into reason_id;
  insert into public.downtime_events(factory_id,work_center_id,reason_id)
  values(f,original,reason_id) returning id into downtime_id;
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,original,m1);
  transfer_id := public.transfer_production(f,original,m1,'Borrowed during home pause');
  if (select status from public.work_centers where id=m1)<>'running'
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=m1)
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
  then raise exception 'borrowed_machine_state_failed'; end if;
  perform public.set_line_pause(f,home,false,null);
  if (select status from public.work_centers where id=m1)<>'running'
    or (select line_id from public.work_centers where id=m1)<>home
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
  then raise exception 'borrowed_machine_resume_failed'; end if;

  -- A manual status transition clears the pause marker even if it ends idle.
  update public.work_centers set status='running' where id=m2;
  perform public.set_line_pause(f,home,true,'planned_stop');
  perform public.change_status(f,m2,'offline');
  perform public.change_status(f,m2,'idle');
  if exists(select 1 from private.line_pause_auto_idled where work_center_id=m2)
  then raise exception 'manual_change_marker_not_cleared'; end if;
  perform public.set_line_pause(f,home,false,null);
  if (select status from public.work_centers where id=m2)<>'idle'
    or (select status from public.work_centers where id=stopped)<>'stopped'
  then raise exception 'manual_change_overwritten'; end if;

  raise exception '__rollback_pause_fixture__';
 exception when raise_exception then
  if sqlerrm <> '__rollback_pause_fixture__' then raise; end if;
 end;
end$$;
