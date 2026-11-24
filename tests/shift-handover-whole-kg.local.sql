-- Canonical preview only. Synthetic state and receipts roll back.
begin;
set local statement_timeout='25s';
set local lock_timeout='5s';

do $test$
#variable_conflict use_variable
declare
  fixture jsonb; factory uuid; owner_id uuid; receiver uuid; viewer uuid; material uuid; zero_material uuid;
  request_id uuid; supply_row uuid; original jsonb; other jsonb; stock_work jsonb; handover_work jsonb;
  args jsonb; counts jsonb; handover_id uuid; result jsonb; receipt_args jsonb; receipt_token uuid:=gen_random_uuid();
  existing_evidence text; ledger text; goods_result jsonb; payload jsonb; target jsonb;
begin
  if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>29719
    or current_database()<>'factory_lean_quality_local'
    or lower(replace(current_setting('data_directory'),chr(92),'/'))<>'d:/factorylean/preview/review-20261108/data'
  then raise exception 'unexpected local database';end if;
  select md5(jsonb_agg(to_jsonb(h) order by id)::text) into existing_evidence
    from private.production_shift_handovers h;
  fixture:=mp_test.fixture('whole-kg-handover-'||gen_random_uuid());
  factory:=(fixture->>'factory')::uuid; owner_id:=(fixture->>'owner')::uuid;
  receiver:=(fixture->>'worker')::uuid; viewer:=(fixture->>'viewer')::uuid;
  perform public.update_settings(factory,'Rollback whole-kg verification','UTC',null);
  perform public.configure_working_calendar(factory,127,'00:00','23:59');
  perform public.configure_production_shift(factory,'Counting shift','Counting shift',
    ((clock_timestamp()+interval '1 second') at time zone 'UTC')::time,
    ((clock_timestamp()+interval '4 hours') at time zone 'UTC')::time);
  perform pg_sleep(1.15);
  perform public.production_stock_action(factory,'ENABLE','{}',gen_random_uuid());
  insert into public.materials(factory_id,name,code,unit,inventory_kind)
    values(factory,'Fractional resin','ROLL-KG','kg','RAW_MATERIAL') returning id into material;
  insert into public.materials(factory_id,name,code,unit,inventory_kind)
    values(factory,'Explicit zero additive','ROLL-ZERO','kg','RAW_MATERIAL') returning id into zero_material;
  perform public.receive_warehouse_stock(factory,material,'material','kg',76.55,'opening_balance');
  request_id:=(public.production_stock_action(factory,'REQUEST',jsonb_build_object('rows',
    jsonb_build_array(jsonb_build_object('material',material,'quantity','76.55'))),gen_random_uuid())->>'id')::uuid;
  select r.id into strict supply_row from private.production_supply_rows r where r.request_id=request_id;
  perform public.production_stock_action(factory,'DELIVER',jsonb_build_object('id',request_id,'revision',1,'physical_confirmation',true,
    'rows',jsonb_build_array(jsonb_build_object('id',supply_row,'quantity','76.55'))),gen_random_uuid());
  select md5(jsonb_agg(to_jsonb(m) order by id)::text) into ledger from private.production_stock_movements m where factory_id=factory;
  stock_work:=public.production_stock_work(factory);
  handover_work:=public.production_handover_read(factory);
  if handover_work->>'raw_precision' is distinct from 'whole_kg' then raise exception 'missing precision contract';end if;
  counts:=jsonb_build_array(jsonb_build_object('id',material,'quantity','77'),jsonb_build_object('id',zero_material,'quantity','0'));
  args:=jsonb_build_object('occurrence_key',stock_work#>>'{occurrence,occurrence,occurrence_key}',
    'stock_revision',stock_work->>'stock_revision','goods_revision',handover_work->>'goods_revision',
    'raw',counts,'goods','[]'::jsonb,'note','');
  begin
    perform public.production_handover_action(factory,'HANDOVER_SUBMIT',jsonb_set(args,'{stock_revision}','"stale"'),gen_random_uuid());
    raise exception 'stale stock accepted';
  exception when serialization_failure then
    if sqlerrm<>'production_stock_count_changed' then raise;end if;
  end;
  begin
    perform public.production_handover_action(factory,'HANDOVER_SUBMIT',jsonb_set(args,'{raw,0,quantity}','"76.55"'),gen_random_uuid());
    raise exception 'fractional technician count accepted';
  exception when invalid_parameter_value then
    if sqlerrm<>'production_stock_count_required' then raise;end if;
  end;
  begin
    perform public.production_handover_action(factory,'HANDOVER_SUBMIT',jsonb_set(args,'{raw,0,quantity}','"76"'),gen_random_uuid());
    raise exception 'genuine difference accepted without note';
  exception when invalid_parameter_value then
    if sqlerrm<>'production_stock_investigation_required' then raise;end if;
  end;
  begin
    perform public.production_handover_action(factory,'HANDOVER_SUBMIT',jsonb_set(args,'{raw,1,quantity}','""'),gen_random_uuid());
    raise exception 'blank accepted as zero';
  exception when invalid_parameter_value then
    if sqlerrm<>'production_stock_count_required' then raise;end if;
  end;

  payload:=jsonb_build_object('body','Review planned maintenance','follow_up',false,'maintenance',fixture->'request');
  for target in select value from jsonb_array_elements(jsonb_build_array(
    jsonb_build_object('machine',fixture->'other_machine'),jsonb_build_object('line',fixture->'other_line'),
    '{}'::jsonb,jsonb_build_object('machine',fixture->'machine','line',fixture->'line')))
  loop
    begin
      perform public.production_stock_action(factory,'NOTE',payload||target,gen_random_uuid());
      raise exception 'outside, ambiguous or missing association accepted';
    exception when invalid_parameter_value then
      if sqlerrm<>'handoverMaintenanceMismatch' then raise;end if;
    end;
  end loop;
  perform public.production_stock_action(factory,'NOTE',payload||jsonb_build_object('machine',fixture->'machine'),gen_random_uuid());
  perform public.production_stock_action(factory,'NOTE',payload||jsonb_build_object('line',fixture->'line'),gen_random_uuid());
  handover_id:=(public.production_handover_action(factory,'HANDOVER_SUBMIT',args,gen_random_uuid())->>'id')::uuid;
  original:=public.production_handover_read(factory,handover_id)->'selection';
  select value into strict other from jsonb_array_elements(original->'raw') where value->>'material'=material::text;
  if other->>'expected' is distinct from '76.55' or other->>'actual' is distinct from '77'
    or other->>'difference' is distinct from '0' or other->>'significant' is distinct from 'false'
    or jsonb_array_length(original->'notes')<>2
  then raise exception 'rounded comparison, exact evidence or note links incorrect';end if;
  receipt_args:=jsonb_build_object('handover_id',handover_id,'occurrence_key',args->>'occurrence_key',
    'raw',counts,'goods','[]'::jsonb,'note','');
  begin
    perform public.production_handover_action(factory,'HANDOVER_RECEIVE',receipt_args,gen_random_uuid());
    raise exception 'sender received own handover';
  exception when invalid_parameter_value then
    if sqlerrm<>'handover_requires_incoming' then raise;end if;
  end;
  perform set_config('request.jwt.claim.sub',viewer::text,true);
  begin
    perform public.production_handover_action(factory,'HANDOVER_RECEIVE',receipt_args,gen_random_uuid());
    raise exception 'viewer received handover';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',owner_id::text,true);
  perform public.set_member_direct_permissions(factory,receiver,
    '[{"module":"factory","action":"view"},{"module":"orders","action":"view"},{"module":"orders","action":"edit"}]',
    array(select module||':'||action from public.user_permissions where factory_id=factory and user_id=receiver));
  perform set_config('request.jwt.claim.sub',receiver::text,true);
  begin
    perform public.production_handover_action(factory,'HANDOVER_RECEIVE',
      jsonb_set(receipt_args,'{raw,0,quantity}','"76"'),gen_random_uuid());
    raise exception 'receiver difference accepted without explanation';
  exception when invalid_parameter_value then
    if sqlerrm<>'production_stock_investigation_required' then raise;end if;
  end;
  result:=public.production_handover_action(factory,'HANDOVER_RECEIVE',receipt_args,receipt_token);
  if result is distinct from public.production_handover_action(factory,'HANDOVER_RECEIVE',receipt_args,receipt_token)
  then raise exception 'exact retry failed';end if;
  begin
    perform public.production_handover_action(factory,'HANDOVER_RECEIVE',receipt_args,gen_random_uuid());
    raise exception 'duplicate receipt recorded';
  exception when serialization_failure then
    if sqlerrm<>'handover_already_received' then raise;end if;
  end;
  other:=public.production_handover_read(factory,handover_id)->'selection';
  if other->'raw' is distinct from original->'raw' or other->>'received_at' is null
    or exists(select from jsonb_array_elements(other#>'{receipt,raw}') q where (q->>'significant')::boolean)
    or private.production_stock_quantity(factory,material)<>76.55
    or ledger is distinct from (select md5(jsonb_agg(to_jsonb(m) order by id)::text) from private.production_stock_movements m where factory_id=factory)
    or exists(select from private.production_stock_consumption where factory_id=factory)
    or exists(select from public.finished_goods_movements where factory_id=factory)
  then raise exception 'receipt rewrote outgoing evidence or changed inventory';end if;
  goods_result:=private.shift_exchange_counts('[{"id":"pipe","actual":"4.125"}]',
    '[{"id":"pipe","quantity":"4.12"}]','id','actual',0);
  if goods_result#>>'{0,difference}' is distinct from '-0.005' then raise exception 'goods decimal precision lost';end if;
  goods_result:=private.shift_exchange_counts('[{"material":"legacy","actual":"76.55"}]',
    '[{"id":"legacy","quantity":"77"}]','material','actual',0);
  if goods_result#>>'{0,difference}' is distinct from '0' or goods_result#>>'{0,significant}' is distinct from 'false'
  then raise exception 'legacy count cannot be confirmed at the approved precision';end if;
  if existing_evidence is distinct from (select md5(jsonb_agg(to_jsonb(h) order by id)::text)
    from private.production_shift_handovers h where h.factory_id<>factory)
  then raise exception 'historical handover records changed';end if;
  raise notice 'PASS whole kg, explicit zero, exact inventory evidence, stale revisions, significant differences, separate one-time receipts, goods precision, historical records and database Maintenance validation';
end $test$;

rollback;
