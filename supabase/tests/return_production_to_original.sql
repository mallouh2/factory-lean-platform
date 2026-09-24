-- Focused TESTING fixture; the enclosing exception rolls everything back.
do $$
declare
 f uuid; actor uuid; cat uuid; home uuid; borrowing uuid;
 alt uuid; original uuid; product_id uuid; home_order uuid;
 borrow_order uuid; reason_id uuid; transfer_id uuid; downtime_id uuid;
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
  values(f,product_id,home,'HO-'||tag,'active',100) returning id into home_order;
  insert into public.production_orders(factory_id,product_id,line_id,code,status,target_quantity)
  values(f,product_id,borrowing,'BO-'||tag,'active',100) returning id into borrow_order;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,home,cat,'Home alternative','HA-'||tag,'running',home_order)
  returning id into alt;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,borrowing,cat,'Borrowing original','BR-'||tag,'stopped',borrow_order)
  returning id into original;
  insert into public.downtime_reasons(factory_id,name)
  values(f,'Return failure '||tag) returning id into reason_id;
  insert into public.downtime_events(factory_id,work_center_id,reason_id)
  values(f,original,reason_id) returning id into downtime_id;
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,original,alt);

  perform public.set_line_pause(f,home,true,'borrow_machine');
  transfer_id := public.transfer_production(f,original,alt,'Return after resume');
  perform public.set_line_pause(f,home,false,null);
  if not exists(
    select 1 from public.production_transfers
    where id=transfer_id and ended_at is null
      and alternative_order_captured and alternative_previous_order_id=home_order
  ) or (select order_id from public.work_centers where id=alt)<>borrow_order
    or exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
  then raise exception 'pre_return_assignment_incorrect'; end if;

  -- A rejected status change must not release the borrowed alternative.
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  begin
   perform public.change_status(f,original,'running');
   raise exception 'unauthorized_return_succeeded';
  exception when others then
   if sqlerrm='unauthorized_return_succeeded' then raise; end if;
  end;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  if (select status from public.work_centers where id=original)<>'stopped'
    or (select order_id from public.work_centers where id=alt)<>borrow_order
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
    or not exists(select 1 from public.downtime_events where id=downtime_id and ended_at is null)
  then raise exception 'failed_return_partially_released_transfer'; end if;

  perform public.change_status(f,original,'running');
  if (select status from public.work_centers where id=original)<>'running'
    or (select status from public.work_centers where id=alt)<>'running'
    or (select line_id from public.work_centers where id=alt)<>home
    or (select order_id from public.work_centers where id=alt)<>home_order
    or not exists(select 1 from public.production_transfers
                  where id=transfer_id and ended_at is not null
                    and original_returned_at is not null)
    or not exists(select 1 from public.downtime_events
                  where id=downtime_id and ended_at is not null)
    or exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
    or not exists(select 1 from public.production_lines where id=home and paused_at is null)
  then raise exception 'active_home_return_incomplete'; end if;

  -- Returning while the home line remains paused keeps its physical pause rule.
  perform public.change_status(f,original,'stopped',reason_id);
  perform public.set_line_pause(f,home,true,'borrow_machine');
  transfer_id := public.transfer_production(f,original,alt,'Return while paused');
  perform public.change_status(f,original,'running');
  if (select status from public.work_centers where id=alt)<>'idle'
    or (select order_id from public.work_centers where id=alt)<>home_order
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
    or not exists(select 1 from public.production_lines where id=home and paused_at is not null)
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
  then raise exception 'paused_home_return_incomplete'; end if;

  raise exception '__rollback_return_production_fixture__';
 exception when raise_exception then
  if sqlerrm <> '__rollback_return_production_fixture__' then raise; end if;
 end;
end$$;
