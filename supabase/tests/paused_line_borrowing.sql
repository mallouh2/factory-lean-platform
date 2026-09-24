-- Focused TESTING check. Every fixture row is rolled back on success.
do $$
declare
 f uuid; actor uuid; cat uuid; other_cat uuid;
 home uuid; borrow_line uuid; product_id uuid; home_order uuid; borrow_order uuid;
 original uuid; second_original uuid; alt uuid; unconfigured uuid; wrong_cat uuid;
 reason_id uuid; transfer_id uuid; physical_status text;
 tag text := substr(replace(gen_random_uuid()::text,'-',''),1,10);
begin
 select factory_id,user_id into f,actor from public.memberships
 where is_owner and status='approved' order by created_at limit 1;
 select id into cat from public.work_center_categories
 where factory_id=f and not archived limit 1;
 if f is null or cat is null then raise exception 'missing_testing_fixture_owner_or_category'; end if;
 begin
  perform set_config('request.jwt.claim.sub',actor::text,true);
  insert into public.production_lines(factory_id,name,code)
  values(f,'Paused source '||tag,'PS-'||tag) returning id into home;
  insert into public.production_lines(factory_id,name,code)
  values(f,'Borrowing target '||tag,'BT-'||tag) returning id into borrow_line;
  insert into public.products(factory_id,name,code)
  values(f,'Paused borrow product '||tag,'BP-'||tag) returning id into product_id;
  insert into public.production_orders(factory_id,product_id,line_id,code,status,target_quantity)
  values(f,product_id,home,'HOME-'||tag,'active',100) returning id into home_order;
  insert into public.production_orders(factory_id,product_id,line_id,code,status,target_quantity)
  values(f,product_id,borrow_line,'BORROW-'||tag,'active',100) returning id into borrow_order;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,borrow_line,cat,'Stopped original','O-'||tag,'stopped',borrow_order)
  returning id into original;
  insert into public.downtime_reasons(factory_id,name)
  values(f,'Paused borrow failure '||tag) returning id into reason_id;
  insert into public.downtime_events(factory_id,work_center_id,reason_id)
  values(f,original,reason_id);
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,home,cat,'Released alternative','A-'||tag,'idle',home_order)
  returning id into alt;
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,original,alt);

  -- Idle on an unpaused line still cannot borrow across conflicting orders.
  begin
   perform public.transfer_production(f,original,alt,'Unpaused conflict check');
   raise exception 'unpaused_conflict_accepted';
  exception when raise_exception then
   if sqlerrm <> 'incompatible_alternative' then raise; end if;
  end;
  perform public.set_line_pause(f,home,true,'borrow_machine');

  -- Paused status alone never makes a stopped/setup/offline center eligible.
  foreach physical_status in array array['stopped','setup','offline'] loop
   update public.work_centers set status=physical_status where id=alt;
   begin
    perform public.transfer_production(f,original,alt,'Physical status check');
    raise exception 'non_idle_alternative_accepted';
   exception when raise_exception then
    if sqlerrm <> 'incompatible_alternative' then raise; end if;
   end;
  end loop;

  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,home,cat,'Not configured','NC-'||tag,'idle',home_order)
  returning id into unconfigured;
  begin
   perform public.transfer_production(f,original,unconfigured,'Relationship check');
   raise exception 'unconfigured_alternative_accepted';
  exception when raise_exception then
   if sqlerrm <> 'incompatible_alternative' then raise; end if;
  end;
  insert into public.work_center_categories(factory_id,name)
  values(f,'Other category '||tag) returning id into other_cat;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,home,other_cat,'Wrong category','WC-'||tag,'idle',home_order)
  returning id into wrong_cat;
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,original,wrong_cat);
  begin
   perform public.transfer_production(f,original,wrong_cat,'Category check');
   raise exception 'wrong_category_accepted';
  exception when raise_exception then
   if sqlerrm <> 'incompatible_alternative' then raise; end if;
  end;

  -- The eligible machine was running before this pause and is auto-idled.
  update public.work_centers set status='running' where id=alt;
  perform public.set_line_pause(f,home,true,'borrow_machine');
  if (select status from public.work_centers where id=alt)<>'idle'
    or not exists(select 1 from private.line_pause_auto_idled where work_center_id=alt)
  then raise exception 'pause_did_not_release_alternative'; end if;
  transfer_id := public.transfer_production(f,original,alt,'Borrow from paused home line');
  if not exists(select 1 from public.production_transfers
                where id=transfer_id and ended_at is null and alternative_id=alt)
    or (select status from public.work_centers where id=alt)<>'running'
    or (select line_id from public.work_centers where id=alt)<>home
    or not exists(select 1 from public.production_lines where id=home and paused_at is not null)
    or not exists(select 1 from public.work_centers where id=original and line_id=borrow_line)
  then raise exception 'paused_line_transfer_failed'; end if;

  -- Even if the borrowed machine later becomes idle, its open transfer owns it.
  update public.work_centers set status='idle' where id=alt;
  insert into public.work_centers(factory_id,line_id,category_id,name,code,status,order_id)
  values(f,borrow_line,cat,'Second stopped original','O2-'||tag,'stopped',borrow_order)
  returning id into second_original;
  insert into public.downtime_events(factory_id,work_center_id,reason_id)
  values(f,second_original,reason_id);
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
  values(f,second_original,alt);
  begin
   perform public.transfer_production(f,second_original,alt,'Already borrowed check');
   raise exception 'already_borrowed_accepted';
  exception when raise_exception then
   if sqlerrm <> 'incompatible_alternative' then raise; end if;
  end;
  if not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
  then raise exception 'existing_transfer_was_ended'; end if;

  perform public.change_status(f,original,'running');
  if not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
    or (select line_id from public.work_centers where id=alt)<>home
  then raise exception 'transfer_end_or_home_line_changed'; end if;
  raise exception '__rollback_borrow_fixture__';
 exception when raise_exception then
  if sqlerrm <> '__rollback_borrow_fixture__' then raise; end if;
 end;
end$$;
