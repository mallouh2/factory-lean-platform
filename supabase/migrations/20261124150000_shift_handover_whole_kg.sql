begin;

-- Raw counting precision is confined to the two-sided handover. Goods remain exact.

create or replace function private.shift_exchange_counts(rows jsonb, counts jsonb, row_key text, expected_key text, threshold numeric)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb; whole_kg boolean:=row_key='material';
begin
  if jsonb_typeof(counts) is distinct from 'array' or jsonb_array_length(counts)<>jsonb_array_length(rows)
    or exists(select 1 from jsonb_array_elements(counts) c
      where jsonb_typeof(c) is distinct from 'object' or jsonb_typeof(c->'id') is distinct from 'string'
        or jsonb_typeof(c->'quantity') is distinct from 'string'
        or (c->>'quantity')!~(case when whole_kg then '^[0-9]{1,24}$' else '^[0-9]{1,24}(\.[0-9]{1,12})?$' end))
    or (select count(distinct c->>'id') from jsonb_array_elements(counts) c)<>jsonb_array_length(counts)
    or exists(select 1 from jsonb_array_elements(rows) r
      where not exists(select 1 from jsonb_array_elements(counts) c where c->>'id'=r->>row_key))
  then raise exception 'production_stock_count_required' using errcode='22023';end if;
  select coalesce(jsonb_agg(r||jsonb_build_object('actual',trim_scale(actual)::text,
    'difference',trim_scale(actual-expected)::text,
    'significant',actual<>expected and (expected=0 or abs(actual-expected)>expected*threshold/100))
    || case when whole_kg then jsonb_build_object('count_precision','whole_kg',
      'comparison_expected',expected::text,
      'percent',case when expected<>0 then trim_scale((actual-expected)*100/expected)::text end)
    else '{}'::jsonb end
    order by ordinal),'[]'::jsonb) into result
  from jsonb_array_elements(rows) with ordinality as evidence(r,ordinal)
  join jsonb_array_elements(counts) c on c->>'id'=r->>row_key
  cross join lateral (select case when whole_kg then round((r->>expected_key)::numeric) else (r->>expected_key)::numeric end expected,(c->>'quantity')::numeric actual) q;
  return result;
end $$;

create or replace function public.production_handover_read(factory uuid, target uuid default null, history_page integer default 1)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare goods jsonb; occ jsonb; current_id uuid; pending jsonb; history jsonb;
begin
  perform private.require_permission(factory,'factory','view');
  perform private.require_permission(factory,'orders','view');
  if history_page is null or history_page not between 1 and 10000 then
    raise exception 'material_invalid' using errcode='22023';
  end if;
  if target is not null then
    return jsonb_build_object('selection',private.shift_exchange_detail(factory,target));
  end if;
  goods:=private.shift_handover_goods(factory);
  occ:=private.resolve_production_occurrence(factory,statement_timestamp());
  select handover_id into current_id from private.production_shift_exchanges
    where factory_id=factory and occurrence_key=occ#>>'{occurrence,occurrence_key}';
  select coalesce(jsonb_agg(private.shift_exchange_detail(factory,e.handover_id) order by h.created_at desc,h.id),'[]') into pending
    from (select x.handover_id from private.production_shift_exchanges x
      join private.production_shift_handovers h on h.factory_id=x.factory_id and h.id=x.handover_id
      where x.factory_id=factory and x.received_at is null order by h.created_at desc,h.id limit 30) e
    join private.production_shift_handovers h on h.factory_id=factory and h.id=e.handover_id;
  select coalesce(jsonb_agg(private.shift_exchange_detail(factory,h.id) order by h.created_at desc,h.id),'[]') into history
    from (select h.id,h.created_at from private.production_shift_handovers h
      join private.production_shift_exchanges e on e.factory_id=h.factory_id and e.handover_id=h.id
      where e.factory_id=factory and e.received_at is not null order by h.created_at desc,h.id
      limit 20 offset (history_page-1)*20) h;
  return jsonb_build_object('raw_precision','whole_kg','goods',goods,'goods_revision',md5(goods::text),'occurrence',occ,
    'current',private.shift_exchange_detail(factory,current_id),'pending',pending,'history',history,
    'history_total',(select count(*) from private.production_shift_exchanges where factory_id=factory and received_at is not null));
end $$;

create or replace function public.production_handover_action(factory uuid, operation text, payload jsonb, request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
#variable_conflict use_variable
declare occ jsonb; goods jsonb; raw jsonb; notes jsonb; receipt_note text;
  result jsonb; stock_work jsonb; reference uuid; e private.production_shift_exchanges;
  old private.production_stock_commands; intent jsonb:=jsonb_build_object('operation',operation,'payload',payload);
  threshold numeric;
begin
  perform private.require_permission(factory,'factory','view');
  perform private.require_permission(factory,'orders','view');
  perform private.require_permission(factory,'orders','edit');
  if request_id is null or operation is null or operation not in ('HANDOVER_SUBMIT','HANDOVER_RECEIVE')
    or jsonb_typeof(payload) is distinct from 'object' or octet_length(payload::text)>120000
    or exists(select 1 from jsonb_object_keys(payload) k where k<>all(case when operation='HANDOVER_SUBMIT'
      then array['occurrence_key','stock_revision','goods_revision','raw','goods','note']
      else array['handover_id','occurrence_key','raw','goods','note'] end))
  then raise exception 'material_invalid' using errcode='22023';end if;
  -- Production recording, Quality and Warehouse receipts take the factory
  -- lock first. Match that order before snapshotting their outstanding goods.
  if operation='HANDOVER_SUBMIT' then perform pg_advisory_xact_lock(hashtextextended(factory::text,0));end if;
  perform private.production_stock_lock(factory);
  perform private.require_permission(factory,'factory','view');
  perform private.require_permission(factory,'orders','view');
  perform private.require_permission(factory,'orders','edit');
  select * into old from private.production_stock_commands c where c.factory_id=factory and c.retry_id=request_id;
  if found then
    if old.actor<>auth.uid() or old.intent<>intent then raise exception 'request_conflict' using errcode='40001';end if;
    return old.result;
  end if;
  if not private.production_stock_enabled(factory) then raise exception 'production_stock_disabled' using errcode='22023';end if;
  occ:=private.resolve_production_occurrence(factory,clock_timestamp());
  if occ->>'available' is distinct from 'true' then raise exception 'recording_shift_unavailable' using errcode='22023';end if;
  if occ#>>'{occurrence,occurrence_key}' is distinct from payload->>'occurrence_key' then
    raise exception 'handover_shift_changed' using errcode='40001';
  end if;
  receipt_note:=btrim(coalesce(payload->>'note',''));
  if length(receipt_note)>2000 then raise exception 'material_invalid' using errcode='22023';end if;
  if operation='HANDOVER_SUBMIT' then
    if exists(select 1 from private.production_shift_exchanges x where x.factory_id=factory and x.occurrence_key=payload->>'occurrence_key')
    then raise exception 'handover_already_submitted' using errcode='40001';end if;
    goods:=private.shift_handover_goods(factory);
    if md5(goods::text) is distinct from payload->>'goods_revision' then
      raise exception 'handover_goods_changed' using errcode='40001';
    end if;
    goods:=private.shift_exchange_counts(goods,payload->'goods','id','expected',0);
    if length(receipt_note)<3 and exists(select 1 from jsonb_array_elements(goods) g where (g->>'significant')::boolean)
    then raise exception 'production_stock_investigation_required' using errcode='22023';end if;
    -- Keep exact ledger balances in the snapshot and round only the counting comparison.
    stock_work:=public.production_stock_work(factory);
    if stock_work->>'stock_revision' is distinct from payload->>'stock_revision' then
      raise exception 'production_stock_count_changed' using errcode='40001';
    end if;
    threshold:=(stock_work->>'deviation_percent')::numeric;
    select coalesce(jsonb_agg(jsonb_build_object(
      'material',s->'id','name',s->'name','unit',s->'unit','expected',s->'physical',
      'reserved',s->'reserved','unreserved',s->'available') order by ordinal),'[]')
      into raw from jsonb_array_elements(stock_work->'stocks') with ordinality stock(s,ordinal);
    if jsonb_array_length(raw)>500 then raise exception 'material_invalid' using errcode='22023';end if;
    raw:=private.shift_exchange_counts(raw,payload->'raw','material','expected',threshold);
    if length(receipt_note)<3 and exists(select 1 from jsonb_array_elements(raw) c where (c->>'significant')::boolean)
    then raise exception 'production_stock_investigation_required' using errcode='22023';end if;
    if private.resolve_production_occurrence(factory,clock_timestamp())#>>'{occurrence,occurrence_key}'
      is distinct from payload->>'occurrence_key'
    then raise exception 'handover_shift_changed' using errcode='40001';end if;
    insert into private.production_shift_handovers(factory_id,occurrence,counts,note,actor)
      values(factory,occ->'occurrence',raw,receipt_note,auth.uid()) returning id into reference;
    select coalesce(jsonb_agg(to_jsonb(n)||jsonb_build_object('author',a.display_name) order by n.created_at,n.id),'[]') into notes
      from private.production_shift_notes n left join public.memberships a on a.factory_id=n.factory_id and a.user_id=n.actor
      where n.factory_id=factory and n.occurrence->>'occurrence_key'=payload->>'occurrence_key';
    insert into private.production_shift_exchanges(factory_id,handover_id,occurrence_key,goods,notes,deviation_percent)
      values(factory,reference,payload->>'occurrence_key',goods,notes,threshold);
  else
    reference:=(payload->>'handover_id')::uuid;
    select x.* into e from private.production_shift_exchanges x
      where x.factory_id=factory and x.handover_id=reference for update;
    if not found then raise exception 'material_invalid' using errcode='22023';end if;
    if e.receipt is not null then raise exception 'handover_already_received' using errcode='40001';end if;
    if exists(select 1 from private.production_shift_handovers h where h.factory_id=factory and h.id=reference and h.actor=auth.uid())
    then raise exception 'handover_requires_incoming' using errcode='22023';end if;
    select counts into raw from private.production_shift_handovers where factory_id=factory and id=reference;
    raw:=private.shift_exchange_counts(raw,payload->'raw','material','actual',e.deviation_percent);
    goods:=private.shift_exchange_counts(e.goods,payload->'goods','id','actual',0);
    if length(receipt_note)<3 and exists(select 1 from jsonb_array_elements(raw||goods) c where (c->>'significant')::boolean)
    then raise exception 'production_stock_investigation_required' using errcode='22023';end if;
    update private.production_shift_exchanges set receipt=jsonb_build_object('occurrence',occ->'occurrence','raw',raw,'goods',goods,'note',receipt_note),
      received_by=auth.uid(),received_at=clock_timestamp() where factory_id=factory and handover_id=reference;
  end if;
  result:=jsonb_build_object('id',reference,'stock_adjusted',false);
  insert into private.production_stock_commands(factory_id,retry_id,actor,intent,result)
    values(factory,request_id,auth.uid(),intent,result);
  insert into private.production_stock_events(factory_id,operation,reference,actor,evidence)
    values(factory,operation,reference,auth.uid(),jsonb_build_object('request_id',request_id));
  return result;
end $$;

-- Validate new associations during note creation and retain existing note history.
create function private.guard_shift_note_maintenance() returns trigger
language plpgsql set search_path='' as $$
declare request_line uuid; request_machine uuid; current_line uuid;
begin
  if (new.line_id is null)=(new.machine_id is null) or new.item_id is not null then
    raise exception 'handoverMaintenanceMismatch' using errcode='22023';
  end if;
  select r.line_id,r.work_center_id into request_line,request_machine
  from public.maintenance_requests r
  where r.factory_id=new.factory_id and r.id=new.maintenance_request_id
    and r.status in ('OPEN','ASSIGNED','IN_PROGRESS','COMPLETED')
  for share;
  if not found then raise exception 'handoverMaintenanceMismatch' using errcode='22023';end if;
  if new.machine_id is not null then
    if new.machine_id=request_machine then return new;end if;
  else
    if new.line_id=request_line then return new;end if;
    select c.line_id into current_line from public.work_centers c
      where c.factory_id=new.factory_id and c.id=request_machine for share;
    if new.line_id=current_line then return new;end if;
  end if;
  raise exception 'handoverMaintenanceMismatch' using errcode='22023';
end $$;

revoke all on function private.guard_shift_note_maintenance() from public,anon,authenticated,service_role;
create trigger guard_shift_note_maintenance before insert on private.production_shift_notes
for each row when (new.maintenance_request_id is not null)
execute function private.guard_shift_note_maintenance();

commit;
