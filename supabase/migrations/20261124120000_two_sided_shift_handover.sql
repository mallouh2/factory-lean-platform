begin;

-- The existing immutable handover is the source for the outgoing raw count.
-- This extension stores the remaining handover evidence and one receipt only.
alter table private.production_shift_handovers add unique (factory_id,id);
create table private.production_shift_exchanges (
  factory_id uuid not null,
  handover_id uuid not null,
  occurrence_key text not null,
  goods jsonb not null,
  notes jsonb not null,
  deviation_percent numeric not null,
  receipt jsonb,
  received_by uuid references auth.users(id),
  received_at timestamptz,
  primary key (factory_id,handover_id),
  unique (factory_id,occurrence_key),
  foreign key (factory_id,handover_id) references private.production_shift_handovers(factory_id,id),
  check ((receipt is null)=(received_by is null) and (receipt is null)=(received_at is null))
);
alter table private.production_shift_exchanges enable row level security;
revoke all on private.production_shift_exchanges from public,anon,authenticated,service_role;

create function private.guard_shift_exchange() returns trigger
language plpgsql set search_path='' as $$
begin
  if TG_OP='DELETE' then raise exception 'immutable_production_stock'; end if;
  if old.receipt is not null or new.receipt is null or
    (to_jsonb(old)-array['receipt','received_by','received_at']) is distinct from
    (to_jsonb(new)-array['receipt','received_by','received_at'])
  then raise exception 'immutable_production_stock'; end if;
  return new;
end $$;
create trigger guard_shift_exchange before update or delete on private.production_shift_exchanges
  for each row execute function private.guard_shift_exchange();

-- Warehouse and Quality evidence stays in its authoritative ledger. Only
-- classified outstanding quantities enter the handover, irrespective of shift.
create function private.shift_handover_goods(f uuid) returns jsonb
language sql stable set search_path='' as $$
  with manufactured as (
    select h.id,h.entry_id,h.item_id,h.unit,h.factory_id,q.quality,g.row,
      private.output_received(f,h.id,g.row->>'id') received
    from private.manufactured_outputs h
    cross join lateral (select private.output_quality(f,h.id) quality) q
    cross join lateral jsonb_array_elements(coalesce(q.quality->'groups',
      (select v.result->'groups' from private.manufactured_output_events v
       where v.factory_id=f and v.output_id=h.id and v.operation='CORRECTION'
       order by v.revision desc limit 1),h.recorded_groups)) g(row)
    where h.factory_id=f
  ), quantities as (
    select m.entry_id,m.unit,
      case when m.quality is null then 'quality_pending'
           when private.output_group_held(f,m.id,(m.row->>'id')::uuid) then 'quality_held'
           when jsonb_array_length(m.row->'missing_operations')>0 then 'unfinished'
           else 'approved' end quality,
      case when m.received>0 then 'partially_received'
           when m.quality is null then 'awaiting_quality'
           else 'awaiting_receipt' end warehouse,
      greatest(0,case when m.quality is null or private.output_group_held(f,m.id,(m.row->>'id')::uuid)
           then (m.row->>'quantity')::numeric else (m.row->>'released')::numeric end - m.received) quantity
    from manufactured m
    union all
    select r.entry_id,rp.unit,'legacy_finished','awaiting_acknowledgment',
      greatest(0,least(r.received_good, greatest(coalesce(rp.accepted_good,rp.effective_good),0)))
    from public.finished_goods_entry_receipts r
    join private.production_reporting_entries rp on rp.factory_id=f and rp.id=r.entry_id
    where r.factory_id=f and not exists(select 1 from private.manufactured_outputs h where h.factory_id=f and h.entry_id=r.entry_id)
      and not exists(select 1 from public.production_receipt_acknowledgments a where a.factory_id=f and a.entry_id=r.entry_id)
    union all
    select u.source_entry_id,rp.unit,
      case when u.quality_rejection_id is null then 'unfinished' else 'rejected_rework' end,
      case when u.warehouse_quantity>0 then 'partially_received' else 'awaiting_receipt' end,
      greatest(0,u.quantity_available-u.warehouse_quantity)
    from public.unfinished_lots u
    join private.production_reporting_entries rp on rp.factory_id=f and rp.id=u.source_entry_id
    where u.factory_id=f and u.manufactured_group_id is null
      and not exists(select 1 from private.manufactured_outputs h where h.factory_id=f and h.entry_id=u.source_entry_id)
  ), grouped as (
    select r.order_id,max(r.item_code) item_code,r.product_id,max(r.product_name) product_name,
      max(r.product_name_ar) product_name_ar,r.line_id,max(r.line_name) line_name,max(r.line_name_ar) line_name_ar,
      q.unit,q.quality,q.warehouse,sum(q.quantity) quantity
    from quantities q join private.production_reporting_entries r on r.factory_id=f and r.id=q.entry_id
    where q.quantity>0
    group by r.order_id,r.product_id,r.line_id,q.unit,q.quality,q.warehouse
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',md5(jsonb_build_array(order_id,line_id,unit,quality,warehouse)::text),'item_id',order_id,'code',item_code,
    'product',product_name,'product_ar',product_name_ar,'line',line_name,'line_ar',line_name_ar,
    'unit',unit,'quality',quality,'warehouse',warehouse,'expected',trim_scale(quantity)::text)
    order by item_code,line_id,unit,quality,warehouse),'[]'::jsonb)
  from grouped
$$;

-- Count every listed row exactly once. Blank, omitted and duplicate counts
-- require correction rather than being interpreted as confirmed zero.
create function private.shift_exchange_counts(rows jsonb, counts jsonb, row_key text, expected_key text, threshold numeric)
returns jsonb language plpgsql immutable set search_path='' as $$
declare result jsonb;
begin
  if jsonb_typeof(counts) is distinct from 'array' or jsonb_array_length(counts)<>jsonb_array_length(rows)
    or exists(select 1 from jsonb_array_elements(counts) c
      where jsonb_typeof(c) is distinct from 'object' or jsonb_typeof(c->'id') is distinct from 'string'
        or jsonb_typeof(c->'quantity') is distinct from 'string'
        or (c->>'quantity')!~'^[0-9]{1,24}(\.[0-9]{1,12})?$')
    or (select count(distinct c->>'id') from jsonb_array_elements(counts) c)<>jsonb_array_length(counts)
    or exists(select 1 from jsonb_array_elements(rows) r
      where not exists(select 1 from jsonb_array_elements(counts) c where c->>'id'=r->>row_key))
  then raise exception 'production_stock_count_required' using errcode='22023';end if;
  select coalesce(jsonb_agg(r||jsonb_build_object('actual',trim_scale(actual)::text,
    'difference',trim_scale(actual-expected)::text,
    'significant',actual<>expected and (expected=0 or abs(actual-expected)>expected*threshold/100))
    order by ordinal),'[]'::jsonb) into result
  from jsonb_array_elements(rows) with ordinality as evidence(r,ordinal)
  join jsonb_array_elements(counts) c on c->>'id'=r->>row_key
  cross join lateral (select (r->>expected_key)::numeric expected,(c->>'quantity')::numeric actual) q;
  return result;
end $$;

create function private.shift_exchange_detail(f uuid, target uuid) returns jsonb
language sql stable set search_path='' as $$
  select jsonb_build_object('id',e.handover_id,'occurrence',h.occurrence,'raw',h.counts,'note',h.note,
    'goods',e.goods,'notes',(select coalesce(jsonb_agg(case when private.has_permission(f,'maintenance','view')
      then n else n-'maintenance_request_id' end order by ordinal),'[]')
      from jsonb_array_elements(e.notes) with ordinality v(n,ordinal)),
    'deviation_percent',e.deviation_percent,'submitted_at',h.created_at,
    'submitted_by',a.display_name,'submitter_id',h.actor,'receipt',e.receipt,
    'received_at',e.received_at,'received_by',b.display_name)
  from private.production_shift_exchanges e
  join private.production_shift_handovers h on h.factory_id=f and h.id=e.handover_id
  left join public.memberships a on a.factory_id=f and a.user_id=h.actor
  left join public.memberships b on b.factory_id=f and b.user_id=e.received_by
  where e.factory_id=f and e.handover_id=target
$$;

create function public.production_handover_read(factory uuid, target uuid default null, history_page integer default 1)
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
  return jsonb_build_object('goods',goods,'goods_revision',md5(goods::text),'occurrence',occ,
    'current',private.shift_exchange_detail(factory,current_id),'pending',pending,'history',history,
    'history_total',(select count(*) from private.production_shift_exchanges where factory_id=factory and received_at is not null));
end $$;

create function public.production_handover_orders(factory uuid, search text default '', selected uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.require_permission(factory,'factory','view');
  perform private.require_permission(factory,'orders','view');
  if length(coalesce(search,''))>100 then raise exception 'material_invalid' using errcode='22023';end if;
  select coalesce(jsonb_agg(to_jsonb(q) order by q.rank,q.created_at desc,q.id),'[]') into result from (
    select o.id,o.code,o.status,o.created_at,p.name product,p.name_ar product_ar,l.name line,l.name_ar line_ar,
      case when o.id=selected then 0 when o.status='active' then 1 when o.status='planned' then 2 else 3 end rank
    from public.production_orders o join public.products p on p.factory_id=factory and p.id=o.product_id
    left join public.production_lines l on l.factory_id=factory and l.id=coalesce(o.actual_line_id,o.line_id)
    where o.factory_id=factory and (o.id=selected or position(lower(coalesce(search,'')) in
      lower(concat_ws(' ',o.code,p.name,p.name_ar,l.name,l.name_ar,o.status)))>0)
    order by rank,o.created_at desc,o.id limit 40
  ) q;
  return jsonb_build_object('orders',result);
end $$;

create function public.production_handover_action(factory uuid, operation text, payload jsonb, request_id uuid)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
#variable_conflict use_variable
declare occ jsonb; goods jsonb; raw jsonb; notes jsonb; receipt_note text;
  result jsonb; outgoing jsonb; reference uuid; e private.production_shift_exchanges;
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
    if jsonb_typeof(payload->'raw') is distinct from 'array' then raise exception 'production_stock_count_required' using errcode='22023';end if;
    select coalesce(jsonb_agg(jsonb_build_object('material',c->'id','quantity',c->'quantity')),'[]') into raw
      from jsonb_array_elements(payload->'raw') c;
    outgoing:=public.production_stock_action(factory,'HANDOVER',
      jsonb_build_object('stock_revision',payload->'stock_revision','counts',raw,'note',receipt_note),gen_random_uuid());
    reference:=(outgoing->>'id')::uuid;
    if not exists(select 1 from private.production_shift_handovers h where h.factory_id=factory and h.id=reference
      and h.occurrence->>'occurrence_key'=payload->>'occurrence_key')
    then raise exception 'handover_shift_changed' using errcode='40001';end if;
    select coalesce((select p.deviation_percent from private.production_material_policy p where p.factory_id=factory),0) into threshold;
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

revoke all on function private.guard_shift_exchange(),private.shift_handover_goods(uuid),
  private.shift_exchange_counts(jsonb,jsonb,text,text,numeric),private.shift_exchange_detail(uuid,uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.production_handover_read(uuid,uuid,integer),public.production_handover_orders(uuid,text,uuid),
  public.production_handover_action(uuid,text,jsonb,uuid) from public,anon,authenticated,service_role;
grant execute on function public.production_handover_read(uuid,uuid,integer),public.production_handover_orders(uuid,text,uuid),
  public.production_handover_action(uuid,text,jsonb,uuid) to authenticated;

commit;
