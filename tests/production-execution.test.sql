-- TESTING only. Execute as a single transaction; all fixtures roll back.
begin;

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
    limit 1;
  if f is null then raise exception 'TESTING approved orders:edit member unavailable'; end if;
  perform set_config('request.jwt.claim.sub',actor::text,true);

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
  req_id:=public.create_production_request(f,prefix||' request','normal',null,'',
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
  perform pg_temp.expect_execution_error(format(
    'select public.finish_product_item(%L::uuid,%L::uuid)',f,item_a),
    'execution_not_running');
  perform public.start_product_item(f,item_b);
  if (select status from public.production_orders where id=item_b)<>'active' then
    raise exception 'queue did not advance'; end if;

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
