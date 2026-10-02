-- TESTING only. Execute as a single transaction; all fixtures roll back.
begin;

-- Inject a center-write failure to verify the entire execution RPC rolls back.
create function pg_temp.fail_execution_projection()
returns trigger language plpgsql as $$
begin
  if current_setting('qa.fail_execution_projection',true)='yes'
    and (new.order_id is not null or old.order_id is not null)
    then raise exception 'qa_projection_failure'; end if;
  return new;
end;
$$;
create trigger z_qa_projection_failure before update on public.work_centers
  for each row execute function pg_temp.fail_execution_projection();

create function pg_temp.expect_execution_error(statement text, expected text)
returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if sqlerrm=expected then return; end if;
    raise exception 'expected %, got %',expected,sqlerrm;
  end;
  raise exception 'expected % but command succeeded',expected;
end;
$$;

do $verify$
declare
  f uuid; actor uuid; other_factory uuid := gen_random_uuid();
  product_a uuid; product_b uuid; product_c uuid; line_a uuid; line_b uuid;
  req_id uuid; item_a uuid; item_b uuid; item_c uuid;
  planned_start timestamptz := now()+interval '35 days';
  planned_finish timestamptz := now()+interval '36 days';
  recorded_start timestamptz; recorded_finish timestamptz;
  before_time timestamptz; after_time timestamptz; revision_count integer;
  prefix text := 'EXEC-'||substr(replace(gen_random_uuid()::text,'-',''),1,12);
  category uuid; other_category uuid; source_center uuid; spare_center uuid;
  wrong_center uuid; home_spare uuid; transfer_id uuid; stop_id uuid;
begin
  select m.factory_id,m.user_id into f,actor
    from public.memberships m join public.factories fac on fac.id=m.factory_id
    where fac.is_demo and m.status='approved'
      and exists(select 1 from public.user_permissions p
        where p.factory_id=m.factory_id and p.user_id=m.user_id
          and p.module='orders' and p.action='edit')
      and exists(select 1 from public.user_permissions p
        where p.factory_id=m.factory_id and p.user_id=m.user_id
          and p.module='orders' and p.action='create')
      and exists(select 1 from public.user_permissions p
        where p.factory_id=m.factory_id and p.user_id=m.user_id
          and p.module='centers' and p.action='edit')
    limit 1;
  if f is null then raise exception 'TESTING approved orders:edit member unavailable'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);

  -- Execution regression fixtures do not depend on live shift setup; rolled back.
  update public.production_shifts set archived=true where factory_id=f and not archived;

  insert into public.products(factory_id,name,code,unit)
    values(f,prefix||' A',prefix||'-A','piece') returning id into product_a;
  insert into public.products(factory_id,name,code,unit)
    values(f,prefix||' B',prefix||'-B','piece') returning id into product_b;
  insert into public.products(factory_id,name,code,unit)
    values(f,prefix||' C',prefix||'-C','piece') returning id into product_c;
  insert into public.production_lines(factory_id,name,code)
    values(f,prefix||' line',prefix||'-L1') returning id into line_a;
  insert into public.production_lines(factory_id,name,code)
    values(f,prefix||' other line',prefix||'-L2') returning id into line_b;
  insert into public.work_center_categories(factory_id,name)
    values(f,prefix||' category') returning id into category;
  insert into public.work_center_categories(factory_id,name)
    values(f,prefix||' other category') returning id into other_category;
  insert into public.work_centers(factory_id,name,code,line_id,category_id)
    values(f,prefix||' source',prefix||'-M',line_a,category) returning id into source_center;
  insert into public.work_centers(factory_id,name,code,line_id,category_id)
    values(f,prefix||' spare',prefix||'-S',line_b,category) returning id into spare_center;
  insert into public.work_centers(factory_id,name,code,category_id)
    values(f,prefix||' wrong',prefix||'-W',other_category) returning id into wrong_center;
  insert into public.work_centers(factory_id,name,code,line_id,category_id)
    values(f,prefix||' home spare',prefix||'-HS',line_a,category) returning id into home_spare;
  insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
    values(f,spare_center,product_a,100,'piece');
  perform public.configure_center_alternatives(f,source_center,array[spare_center]);
  req_id:=public.create_production_request(f,prefix||' request','normal',null,'QA internal production reason',
    jsonb_build_array(
      jsonb_build_object('product_id',product_a,'quantity',10,'unit','piece'),
      jsonb_build_object('product_id',product_b,'quantity',10,'unit','piece'),
      jsonb_build_object('product_id',product_c,'quantity',10,'unit','piece')));
  select id into item_a from public.production_orders where request_id=req_id and product_id=product_a;
  select id into item_b from public.production_orders where request_id=req_id and product_id=product_b;
  select id into item_c from public.production_orders where request_id=req_id and product_id=product_c;
  update public.production_orders set line_id=line_a,start_time=planned_start,
    expected_finish=planned_finish where id=item_a;
  update public.production_orders set line_id=line_a,
    start_time=planned_start+interval '1 day',
    expected_finish=planned_finish+interval '1 day' where id=item_b;
  update public.production_orders set line_id=line_b,start_time=planned_start,
    expected_finish=planned_finish where id=item_c;
  update public.production_orders set planning_locked_at=now(),
    planning_locked_by=actor where id=item_a;
  select count(*) into revision_count from public.production_plan_revisions
    where item_id in (item_a,item_b,item_c);

  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,item_b),
    'execution_out_of_sequence');
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,gen_random_uuid()),
    'not_found');
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,req_id),
    'not_found');
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',other_factory,item_a),
    'permission_denied');
  perform pg_temp.expect_execution_error(format(
    'select public.finish_product_item(%L::uuid,%L::uuid)',f,item_a),
    'execution_not_running');
  perform pg_temp.expect_execution_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',
    f,'orders',item_a,jsonb_build_object('actual_start',now())),
    'invalid_field');
  perform pg_temp.expect_execution_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',
    f,'orders',item_a,jsonb_build_object('status','active')),
    'execution_use_command');

  perform set_config('qa.fail_execution_projection','yes',true);
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,item_a),
    'qa_projection_failure');
  perform set_config('qa.fail_execution_projection','no',true);
  if not exists(select 1 from public.production_orders where id=item_a
    and status='planned' and actual_start is null)
    or exists(select 1 from public.work_centers where id=source_center and order_id is not null)
  then raise exception 'failed start left partial assignment'; end if;

  before_time:=clock_timestamp();
  perform public.start_product_item(f,item_a);
  after_time:=clock_timestamp();
  select actual_start into recorded_start from public.production_orders where id=item_a;
  if recorded_start<before_time or recorded_start>after_time then
    raise exception 'actual start was not server time'; end if;
  if not exists(select 1 from public.production_orders where id=item_a
    and status='active' and start_time=planned_start
    and expected_finish=planned_finish and planning_locked_at is not null) then
    raise exception 'start changed planned or locked state'; end if;
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,item_a),
    'execution_already_started');
  perform pg_temp.expect_execution_error(format(
    'select public.start_product_item(%L::uuid,%L::uuid)',f,item_b),
    'execution_line_busy');
  if (select count(*) from public.production_plan_revisions
    where item_id in (item_a,item_b,item_c))<>revision_count then
    raise exception 'execution changed planning history'; end if;

  if (select order_id from public.work_centers where id=source_center) is distinct from item_a
    then raise exception 'start did not assign home machine'; end if;
  -- Generic configuration cannot independently replace line execution truth.
  perform public.save_record(f,'centers',source_center,jsonb_build_object('order_id',item_b));
  if (select order_id from public.work_centers where id=source_center) is distinct from item_a
    then raise exception 'generic edit bypassed execution projection'; end if;
  stop_id:=public.stop_machine(f,source_center,'planned',null,'cleaning','QA only');
  insert into public.work_center_alternatives(factory_id,work_center_id,alternative_id)
    values(f,source_center,wrong_center);
  perform pg_temp.expect_execution_error(format(
    'select public.transfer_production(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,source_center,wrong_center,'QA incompatible category'),'incompatible_alternative');
  delete from public.work_center_capabilities where work_center_id=spare_center;
  perform pg_temp.expect_execution_error(format(
    'select public.transfer_production(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,source_center,spare_center,'QA incompatible capability'),'incompatible_alternative');
  insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
    values(f,spare_center,product_a,100,'piece');
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  perform pg_temp.expect_execution_error(format(
    'select public.transfer_production(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,source_center,spare_center,'QA unauthorized transfer'),'permission_denied');
  perform set_config('request.jwt.claim.sub',actor::text,true);
  transfer_id:=public.transfer_production(f,source_center,spare_center,'QA valid transfer');
  -- Output belongs to the borrowing line, not either individual transfer machine.
  perform public.record_production(f,'line',line_a,item_a,
    (select id from public.memberships where factory_id=f and user_id=actor),1,0,'QA transfer line output');
  if not exists(select 1 from public.production_orders where id=item_a and good_quantity=1)
    or not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
    or (select order_id from public.work_centers where id=spare_center) is distinct from item_a
    then raise exception 'recording during transfer changed assignment/lifecycle';end if;
  perform pg_temp.expect_execution_error(format(
    'select public.transfer_production(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,source_center,spare_center,'QA duplicate transfer'),'transfer_already_active');
  perform public.stop_machine(f,spare_center,'planned',null,'cleaning','QA borrower stop');
  if not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is null)
    or not exists(select 1 from public.work_centers where id=spare_center
      and line_id=line_b and order_id=item_a and status='stopped')
  then raise exception 'borrower stop lost assignment'; end if;

  perform set_config('qa.fail_execution_projection','yes',true);
  perform pg_temp.expect_execution_error(format(
    'select public.finish_product_item(%L::uuid,%L::uuid)',f,item_a),
    'qa_projection_failure');
  perform set_config('qa.fail_execution_projection','no',true);
  if not exists(select 1 from public.production_orders where id=item_a
    and status='active' and actual_finish is null)
    or (select order_id from public.work_centers where id=source_center) is distinct from item_a
  then raise exception 'failed finish left partial assignment'; end if;
  before_time:=clock_timestamp();
  perform public.finish_product_item(f,item_a);
  after_time:=clock_timestamp();
  select actual_finish into recorded_finish from public.production_orders where id=item_a;
  if recorded_finish<before_time or recorded_finish>after_time then
    raise exception 'actual finish was not server time'; end if;
  if not exists(select 1 from public.production_orders where id=item_a
    and status='completed' and actual_start=recorded_start
    and start_time=planned_start and expected_finish=planned_finish) then
    raise exception 'finish changed actual start or planned values'; end if;
  if (select order_id from public.work_centers where id=source_center) is not null
    then raise exception 'finish retained stale home assignment'; end if;
  if (select order_id from public.work_centers where id=spare_center) is distinct from item_a
    then raise exception 'finish overwrote open borrowing'; end if;
  perform pg_temp.expect_execution_error(format(
    'select public.transfer_production(%L::uuid,%L::uuid,%L::uuid,%L)',
    f,source_center,wrong_center,'QA no active job'),'invalid_order');
  perform pg_temp.expect_execution_error(format(
    'select public.finish_product_item(%L::uuid,%L::uuid)',f,item_a),
    'execution_not_running');
  perform public.start_product_item(f,item_b);
  if (select status from public.production_orders where id=item_b)<>'active' then
    raise exception 'queue did not advance'; end if;
  if (select order_id from public.work_centers where id=source_center) is distinct from item_b
    then raise exception 'next item did not replace assignment'; end if;
  -- Borrower's own line can start a new item, without stealing its open assignment.
  perform public.start_product_item(f,item_c);
  if (select order_id from public.work_centers where id=spare_center) is distinct from item_a
    then raise exception 'home start stole borrowed machine'; end if;
  perform public.change_status(f,source_center,'running');
  if not exists(select 1 from public.production_transfers where id=transfer_id and ended_at is not null)
    or (select order_id from public.work_centers where id=spare_center) is distinct from item_c
    or (select line_id from public.work_centers where id=spare_center) is distinct from line_b
  then raise exception 'transfer return restored stale home assignment'; end if;

  -- Same-line spare captured the very same order. Returning it after Finish
  -- still clears the completed projection; no physical state is changed by Finish.
  insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit)
    values(f,home_spare,product_b,100,'piece');
  perform public.configure_center_alternatives(f,source_center,array[home_spare]);
  perform public.stop_machine(f,source_center,'planned',null,'cleaning','QA same-line stop');
  transfer_id:=public.transfer_production(f,source_center,home_spare,'QA same-line transfer');
  if (select alternative_previous_order_id from public.production_transfers where id=transfer_id)
    is distinct from item_b then raise exception 'same-line test did not capture equal orders'; end if;
  perform public.finish_product_item(f,item_b);
  if not exists(select 1 from public.work_centers where id=home_spare
    and order_id=item_b and status='running') then
    raise exception 'finish changed open transfer or physical state'; end if;
  perform public.change_status(f,source_center,'running');
  if (select order_id from public.work_centers where id=home_spare) is not null then
    raise exception 'same-line return retained completed assignment'; end if;

  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  perform pg_temp.expect_execution_error(format(
    'select public.finish_product_item(%L::uuid,%L::uuid)',f,item_b),
    'permission_denied');
  perform set_config('request.jwt.claim.sub',actor::text,true);
  if (select count(*) from public.production_plan_revisions
    where item_id in (item_a,item_b,item_c))<>revision_count then
    raise exception 'finish changed planning history'; end if;
end;
$verify$;

rollback;
