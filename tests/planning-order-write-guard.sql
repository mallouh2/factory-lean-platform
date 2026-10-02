-- Run against TESTING only after the guard migration. Every fixture and edit is
-- contained in this transaction; no production request or master data remains.
begin;

create function pg_temp.expect_planning_error(statement text, expected text)
returns void language plpgsql as $$
begin
  begin
    execute statement;
  exception when others then
    if sqlerrm=expected then return; end if;
    raise exception 'expected %, got %', expected, sqlerrm;
  end;
  raise exception 'expected % but the command succeeded', expected;
end;
$$;

do $verify$
declare
  f uuid; actor uuid; category uuid; product_a uuid; product_b uuid; product_c uuid;
  line_a uuid; line_b uuid; center_a uuid; center_b uuid; new_request uuid;
  item_a uuid; item_b uuid; desired timestamptz; first_start timestamptz;
  revised_start timestamptz; actual public.production_orders%rowtype;
  prefix text := 'GUARD-' || substr(replace(gen_random_uuid()::text,'-',''),1,12);
begin
  select m.factory_id,m.user_id into f,actor
    from public.memberships m join public.factories fac on fac.id=m.factory_id
    where fac.is_demo and m.status='approved'
      and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id
        and p.user_id=m.user_id and p.module='orders' and p.action='create')
      and exists(select 1 from public.user_permissions p where p.factory_id=m.factory_id
        and p.user_id=m.user_id and p.module='orders' and p.action='edit')
    limit 1;
  if f is null then raise exception 'TESTING demo factory/member fixture unavailable'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);
  select id into category from public.work_center_categories
    where factory_id=f and not archived limit 1;
  if category is null then raise exception 'TESTING work-center category fixture unavailable'; end if;

  insert into public.products(factory_id,name,code,unit) values
    (f,prefix || ' A',prefix || '-A','piece') returning id into product_a;
  insert into public.products(factory_id,name,code,unit) values
    (f,prefix || ' B',prefix || '-B','piece') returning id into product_b;
  insert into public.products(factory_id,name,code,unit) values
    (f,prefix || ' C',prefix || '-C','piece') returning id into product_c;
  insert into public.production_lines(factory_id,name,code) values
    (f,prefix || ' line',prefix || '-L1') returning id into line_a;
  insert into public.production_lines(factory_id,name,code) values
    (f,prefix || ' other line',prefix || '-L2') returning id into line_b;
  insert into public.work_centers(factory_id,name,code,line_id,category_id) values
    (f,prefix || ' machine',prefix || '-M1',line_a,category) returning id into center_a;
  insert into public.work_center_capabilities
    (factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes) values
    (f,center_a,product_a,60,'piece',30),
    (f,center_a,product_b,60,'piece',30);

  new_request:=public.create_production_request(f,prefix || ' request','normal',null,'QA internal production reason',
    jsonb_build_array(
      jsonb_build_object('product_id',product_a,'quantity',60,'unit','piece'),
      jsonb_build_object('product_id',product_b,'quantity',60,'unit','piece')));
  select id into item_a from public.production_orders
    where request_id=new_request and product_id=product_a;
  select id into item_b from public.production_orders
    where request_id=new_request and product_id=product_b;
  if item_a is null or item_b is null then raise exception 'request fixture failed'; end if;

  -- A generic create or update cannot place an item directly on a line.
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,null,%L::jsonb)',
    f,'orders',jsonb_build_object('line_id',line_a,'start_time',now()+interval '35 days',
      'expected_finish',now()+interval '36 days')),'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',
    f,'orders',item_b,jsonb_build_object('line_id',line_a,
      'start_time',now()+interval '35 days','expected_finish',now()+interval '36 days')),
    'planning_use_plan_command');

  -- Unplanned, never-scheduled product/quantity edits remain valid.
  perform public.save_record(f,'orders',item_b,
    jsonb_build_object('product_id',product_c,'target_quantity',75));
  perform public.save_record(f,'orders',item_b,
    jsonb_build_object('product_id',product_b,'target_quantity',60,
      'line_id',null,'start_time',null,'expected_finish',null));
  select * into actual from public.production_orders where id=item_b;
  if actual.product_id<>product_b or actual.target_quantity<>60 then
    raise exception 'unplanned edit failed'; end if;

  desired:=now()+interval '35 days';
  perform public.plan_product_item(f,item_a,line_a,desired);
  select * into actual from public.production_orders where id=item_a;
  first_start:=actual.start_time;
  if actual.line_id<>line_a
    or actual.start_time<>private.next_working_start(f,desired)
    or actual.expected_finish<>private.finish_after_working_minutes(f,first_start,90)
  then raise exception 'first plan lost calendar/rate/setup validation'; end if;
  if (select count(*) from public.production_plan_revisions
    where factory_id=f and item_id=item_a and event='initial')<>1 then
    raise exception 'initial history missing'; end if;
  if not exists(select 1 from public.production_plan_revisions
    where factory_id=f and item_id=item_a and event='initial'
      and before_line_id is null and after_line_id=line_a
      and after_start=first_start and changed_by=actor and changed_at is not null)
  then raise exception 'initial history details missing'; end if;

  -- A normal generic edit can resubmit unchanged schedule fields.
  perform public.save_record(f,'orders',item_a,jsonb_build_object(
    'code',prefix || '-EDIT','line_id',line_a,'start_time',actual.start_time,
    'expected_finish',actual.expected_finish,'product_id',product_a,'target_quantity',60));
  if (select code from public.production_orders where id=item_a)<>prefix || '-EDIT' then
    raise exception 'non-planning generic edit failed'; end if;
  if (select count(*) from public.production_plan_revisions
    where factory_id=f and item_id=item_a)<>1 then
    raise exception 'unchanged generic edit added history'; end if;

  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('start_time',first_start+interval '1 hour')),
    'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('expected_finish',actual.expected_finish+interval '1 hour')),
    'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('line_id',line_b)),'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('target_quantity',120)),'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('product_id',product_c)),'planning_use_plan_command');

  perform public.set_plan_lock(f,item_a,true);
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('start_time',first_start+interval '1 day')),
    'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.revise_product_plan(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz,%L,%L)',
    f,item_a,line_a,first_start+interval '1 day','priority_change',''),
    'planning_locked');
  perform public.set_plan_lock(f,item_a,false);
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_a,line_a,first_start+interval '1 day'),'planning_reason_required');

  revised_start:=first_start+interval '2 days';
  perform public.revise_product_plan(f,item_a,line_a,revised_start,'priority_change','');
  select * into actual from public.production_orders where id=item_a;
  if actual.start_time<>private.next_working_start(f,revised_start)
    or (select count(*) from public.production_plan_revisions
      where factory_id=f and item_id=item_a and event='replanned')<>1 then
    raise exception 'reasoned replan failed'; end if;
  if not exists(select 1 from public.production_plan_revisions
    where factory_id=f and item_id=item_a and event='replanned'
      and reason_code='priority_change' and before_line_id=line_a
      and after_line_id=line_a and after_start=actual.start_time
      and changed_by=actor and changed_at is not null)
  then raise exception 'replan history details missing'; end if;

  -- The generic guard also holds when a caller supplies the history reason GUC.
  perform set_config('app.plan_reason','priority_change',true);
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('start_time',actual.start_time+interval '1 hour')),
    'planning_use_plan_command');
  perform set_config('app.plan_reason','',true);

  perform public.revise_product_plan(f,item_a,null,null,'management_decision','');
  select * into actual from public.production_orders where id=item_a;
  if actual.line_id is not null or actual.start_time is not null
    or actual.expected_finish is not null
    or (select count(*) from public.production_plan_revisions
      where factory_id=f and item_id=item_a and event='unscheduled')<>1 then
    raise exception 'reasoned unschedule/history failed'; end if;
  if not exists(select 1 from public.production_plan_revisions
    where factory_id=f and item_id=item_a and event='unscheduled'
      and before_line_id=line_a and after_line_id is null
      and reason_code='management_decision' and changed_by=actor
      and changed_at is not null)
  then raise exception 'unschedule history details missing'; end if;
  perform set_config('app.plan_reason','',true);
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('target_quantity',120)),'planning_use_plan_command');
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_a,line_a,revised_start+interval '2 days'),'planning_reason_required');
  perform public.revise_product_plan(f,item_a,line_a,revised_start+interval '2 days',
    'customer_request','');

  -- The dedicated command still rejects incapable lines, unknown units,
  -- conflicting capability rates/setups, and an overlapping booking.
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_b,line_b,revised_start+interval '2 days'),'planning_incompatible_line');
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_b,line_a,(select start_time from public.production_orders where id=item_a)),
    'planning_overlap');
  update public.work_center_capabilities set rate_unit=null
    where work_center_id=center_a and product_id=product_b;
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_b,line_a,revised_start+interval '5 days'),'planning_missing_rate');
  update public.work_center_capabilities set rate_unit='piece'
    where work_center_id=center_a and product_id=product_b;
  insert into public.work_centers(factory_id,name,code,line_id,category_id) values
    (f,prefix || ' second machine',prefix || '-M2',line_a,category) returning id into center_b;
  insert into public.work_center_capabilities
    (factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes) values
    (f,center_b,product_b,60,'piece',15);
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_b,line_a,revised_start+interval '5 days'),'planning_ambiguous_setup');
  update public.work_center_capabilities set rate=120,setup_minutes=30
    where work_center_id=center_b and product_id=product_b;
  perform pg_temp.expect_planning_error(format(
    'select public.plan_product_item(%L::uuid,%L::uuid,%L::uuid,%L::timestamptz)',
    f,item_b,line_a,revised_start+interval '5 days'),'planning_ambiguous_rate');

  -- Restoring a stored schedule from a non-blocking status cannot evade overlap.
  perform public.save_record(f,'orders',item_a,jsonb_build_object('status','cancelled'));
  perform pg_temp.expect_planning_error(format(
    'select public.save_record(%L::uuid,%L,%L::uuid,%L::jsonb)',f,'orders',item_a,
    jsonb_build_object('status','planned')),'planning_use_plan_command');

  raise notice 'Planning generic-write guard and dedicated-command checks passed';
end;
$verify$;

rollback;
select 'Planning guard checks passed; fixture rolled back' as result;
