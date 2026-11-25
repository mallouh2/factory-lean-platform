begin;

-- A draft ID is reserved for eventual materialization in production_orders.
-- Draft rows are not orders, reservations, fulfillment supply or execution work.
create table private.aps_combined_order_drafts (
  factory_id uuid not null references public.factories(id) on delete cascade,
  parent_order_id uuid not null unique,
  product_id uuid not null,
  recipe_id uuid not null,
  candidate_line_id uuid not null,
  unit text not null check (unit in ('meter','piece','kg')),
  total_quantity numeric not null check (total_quantity > 0 and total_quantity < 'Infinity'::numeric),
  intent jsonb not null,
  manufacturing_evidence jsonb not null,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default clock_timestamp(),
  -- Draft evidence must not fence ordinary deletion or reconfiguration of
  -- operational rows. Phase 1B must revalidate every captured relationship.
  primary key (factory_id,parent_order_id)
);

create table private.aps_combined_demand_links (
  factory_id uuid not null,
  parent_order_id uuid not null,
  source_item_id uuid not null,
  source_request_id uuid not null,
  sales_line_id uuid,
  sales_order_id uuid,
  purpose text not null check (purpose in ('SALES_PRODUCTION','STOCK_REPLENISHMENT')),
  proposed_quantity numeric not null,
  eligible_quantity_at_creation numeric not null,
  demand_quantity_at_creation numeric not null,
  undelivered_quantity_at_creation numeric not null,
  requested_by_date timestamptz,
  priority text not null check (priority in ('low','normal','high','urgent')),
  demand_created_at timestamptz not null,
  check ((purpose='SALES_PRODUCTION')=(sales_line_id is not null)),
  check ((sales_line_id is null)=(sales_order_id is null)),
  check (0 < proposed_quantity and proposed_quantity <= eligible_quantity_at_creation
    and eligible_quantity_at_creation <= undelivered_quantity_at_creation
    and undelivered_quantity_at_creation <= demand_quantity_at_creation
    and demand_quantity_at_creation < 'Infinity'::numeric),
  -- Phase 1A claims a source requirement once. Phase 1B owns release and splitting.
  primary key (factory_id,source_item_id),
  foreign key (factory_id,parent_order_id) references private.aps_combined_order_drafts(factory_id,parent_order_id) on delete cascade
);
create index aps_combined_demand_parent on private.aps_combined_demand_links(factory_id,parent_order_id);

alter table private.aps_combined_order_drafts enable row level security;
alter table private.aps_combined_demand_links enable row level security;
revoke all on private.aps_combined_order_drafts,private.aps_combined_demand_links
  from public,anon,authenticated,service_role;

create function private.aps_combined_require_view(f uuid) returns void
language plpgsql stable set search_path='' as $$
begin
  perform private.require_permission(f,'factory','view');
  perform private.require_permission(f,'orders','view');
  perform private.require_permission(f,'sales_orders','view');
  perform private.require_permission(f,'warehouse','view');
end $$;

create function public.aps_combined_order_draft(factory uuid, parent uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
  perform private.aps_combined_require_view(factory);
  select (to_jsonb(d)-'intent')||jsonb_build_object(
    'status','DRAFT',
    'operational',false,
    'demands',(select coalesce(jsonb_agg(to_jsonb(l)||jsonb_build_object(
        'sales_follow_up',l.sales_line_id is not null and l.requested_by_date is null)
      order by (l.sales_line_id is null),
        case l.priority when 'urgent' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
        l.requested_by_date nulls last,l.demand_created_at,l.source_item_id),'[]')
      from private.aps_combined_demand_links l
      where l.factory_id=factory and l.parent_order_id=parent))
  into result from private.aps_combined_order_drafts d where d.factory_id=factory and d.parent_order_id=parent;
  return result;
end $$;

create function public.aps_create_combined_order_draft(factory uuid, parent uuid, candidate_line uuid, demands jsonb)
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare
  existing private.aps_combined_order_drafts;
  item public.production_orders; source_request public.production_requests;
  product public.products; sales_line public.sales_order_lines; sales public.sales_orders;
  candidate_route private.production_input_routes;
  intent jsonb:=jsonb_build_object('line',candidate_line,'demands',demands);
  item_link jsonb; requirements jsonb; recipe uuid; this_recipe uuid;
  evidence jsonb; links jsonb:='[]'; demand_quantity numeric; undelivered numeric; eligible numeric;
  requested timestamptz; demand_created timestamptz; sales_id uuid;
  amount numeric; total numeric:=0; route_count integer; compatible boolean;
begin
  perform private.aps_combined_require_view(factory);
  perform private.require_permission(factory,'orders','edit');
  if parent is null or candidate_line is null or jsonb_typeof(demands) is distinct from 'array' then
    raise exception 'aps_draft_invalid' using errcode='22023';
  end if;
  if jsonb_array_length(demands) not between 2 and 100 or octet_length(demands::text)>32000
    or exists(select from jsonb_array_elements(demands) v where jsonb_typeof(v) is distinct from 'object')
  then raise exception 'aps_draft_invalid' using errcode='22023';end if;
  if exists (
    select from jsonb_array_elements(demands) v
    where not (v ?& array['source_item_id','recipe_id','quantity'])
      or (v-array['source_item_id','recipe_id','quantity'])<>'{}'
      or coalesce(v->>'source_item_id','') !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      or coalesce(v->>'recipe_id','') !~* '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$'
      or jsonb_typeof(v->'quantity') is distinct from 'string'
      or coalesce(v->>'quantity','') !~ '^[0-9]{1,24}(\.[0-9]{1,12})?$'
  ) then raise exception 'aps_draft_invalid' using errcode='22023';end if;
  if (select count(distinct (v->>'source_item_id')::uuid) from jsonb_array_elements(demands) v)
    <>jsonb_array_length(demands)
  then raise exception 'aps_duplicate_demand' using errcode='22023';end if;

  -- Same factory-then-structure lock order as recording and fulfillment.
  if current_setting('transaction_isolation')<>'read committed' then
    raise exception 'aps_draft_retry' using errcode='40001';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(factory::text,0));
  perform private.fulfillment_lock(factory);
  perform private.aps_combined_require_view(factory);
  perform private.require_permission(factory,'orders','edit');
  select * into existing from private.aps_combined_order_drafts d
    where d.factory_id=factory and d.parent_order_id=parent;
  if found then
    if existing.created_by<>auth.uid() or existing.intent<>intent then
      raise exception 'aps_draft_retry_conflict' using errcode='40001';
    end if;
    return public.aps_combined_order_draft(factory,parent);
  end if;
  if exists(select from public.production_orders o where o.factory_id=factory and o.id=parent) then
    raise exception 'aps_draft_invalid' using errcode='22023';
  end if;

  for item_link in select v from jsonb_array_elements(demands) v order by (v->>'source_item_id')::uuid loop
    select * into item from public.production_orders o
      where o.factory_id=factory and o.id=(item_link->>'source_item_id')::uuid for share;
    if not found or item.status<>'planned' or item.actual_start is not null
      or item.produced_quantity<>0 or item.quality_origin_rejection_id is not null
    then raise exception 'aps_demand_ineligible' using errcode='22023';end if;
    if exists(select from private.aps_combined_demand_links l where l.factory_id=factory and l.source_item_id=item.id)
    then raise exception 'aps_duplicate_demand' using errcode='23505';end if;

    if product.id is null then
      select * into product from public.products p where p.factory_id=factory and p.id=item.product_id;
      if not found or item.unit is distinct from product.stock_unit or item.unit not in ('meter','piece','kg')
      then raise exception 'aps_product_or_unit_mismatch' using errcode='22023';end if;

      -- Match the existing static Planning capability/rate/setup checks without scheduling a slot.
      select count(*)>0 and bool_and(c.rate_unit=item.unit and c.rate>0 and c.rate<'Infinity'::numeric)
        and min(c.rate)=max(c.rate) and min(c.setup_minutes)=max(c.setup_minutes)
      into compatible from public.production_lines l join public.work_centers w
        on (w.factory_id,w.line_id)=(l.factory_id,l.id) and not w.archived
      join public.work_center_capabilities c
        on (c.factory_id,c.work_center_id)=(w.factory_id,w.id) and c.product_id=product.id
      where l.factory_id=factory and l.id=candidate_line and not l.archived;
      if not coalesce(compatible,false) then raise exception 'aps_line_ineligible' using errcode='22023';end if;

      -- The material resolver uses the original planned line. Verify the candidate
      -- route separately using the same precedence and compare it with every source.
      select count(*) into route_count
      from private.production_input_routes r join public.production_routing_steps s on s.id=r.routing_step_id
      join public.work_centers w on w.id=s.work_center_id
      where r.factory_id=factory and r.product_id=product.id and w.line_id=candidate_line;
      if route_count>1 then raise exception 'aps_manufacturing_mismatch' using errcode='22023';end if;
      if route_count=1 then
        select r.* into candidate_route
        from private.production_input_routes r join public.production_routing_steps s on s.id=r.routing_step_id
        join public.work_centers w on w.id=s.work_center_id
        where r.factory_id=factory and r.product_id=product.id and w.line_id=candidate_line;
      else
        select r.* into candidate_route from private.production_input_routes r
          where r.factory_id=factory and r.product_id=product.id and r.scope='00000000-0000-0000-0000-000000000000';
      end if;
    elsif item.product_id<>product.id or item.unit<>product.stock_unit then
      raise exception 'aps_product_or_unit_mismatch' using errcode='22023';
    end if;

    requirements:=private.material_requirement_inputs(factory,item.id);
    this_recipe:=(requirements->>'recipe')::uuid;
    if this_recipe is null or requirements ? 'warning' or this_recipe<>(item_link->>'recipe_id')::uuid
      or recipe is not null and this_recipe<>recipe
    then raise exception 'aps_recipe_unverified_or_mismatched' using errcode='22023';end if;
    if requirements->>'mode' is distinct from candidate_route.mode
      or requirements->>'route' is distinct from candidate_route.scope::text
      or requirements->>'route_revision' is distinct from candidate_route.revision::text
    then raise exception 'aps_manufacturing_mismatch' using errcode='22023';end if;
    recipe:=this_recipe;

    select * into strict source_request from public.production_requests r
      where r.factory_id=factory and r.id=item.request_id for share;
    amount:=(item_link->>'quantity')::numeric;
    if amount<=0 or (item.unit='piece' or product.length_parent_id is not null) and amount<>trunc(amount)
    then raise exception 'aps_quantity_invalid' using errcode='22023';end if;

    eligible:=private.ordinary_output_remaining(factory,item.id);
    requested:=source_request.required_by;
    demand_created:=source_request.created_at;
    sales_id:=null;
    if source_request.request_type='SALES_PRODUCTION' then
      select * into sales_line from public.sales_order_lines l
        where l.factory_id=factory and l.id=source_request.sales_order_line_id for share;
      if not found or sales_line.product_id<>product.id or sales_line.unit<>item.unit then
        raise exception 'aps_demand_ineligible' using errcode='22023';
      end if;
      select * into sales from public.sales_orders s where s.factory_id=factory and s.id=sales_line.order_id for share;
      if not found or sales.status<>'approved' then raise exception 'aps_demand_ineligible' using errcode='22023';end if;
      demand_quantity:=sales_line.quantity;
      undelivered:=sales_line.quantity-sales_line.dispatched_quantity;
      requested:=sales.requested_delivery;
      demand_created:=sales.created_at;
      sales_id:=sales.id;
      eligible:=least(eligible,greatest(undelivered-
        coalesce((select sum(r.quantity) from public.finished_goods_reservations r
          where r.factory_id=factory and r.line_id=sales_line.id),0)-
        coalesce((select sum(a.quantity) from public.sales_incoming_allocations a
          where a.factory_id=factory and a.line_id=sales_line.id and a.item_id<>item.id),0),0),
        coalesce((select a.quantity from public.sales_incoming_allocations a
          where a.factory_id=factory and a.line_id=sales_line.id and a.item_id=item.id),0));
    elsif source_request.request_type='STOCK_REPLENISHMENT' and source_request.sales_order_line_id is null then
      demand_quantity:=item.target_quantity;
      undelivered:=eligible;
      -- Stock units already committed to customers cannot be proposed as replenishment.
      eligible:=greatest(eligible-coalesce((select sum(a.quantity) from public.sales_incoming_allocations a
        where a.factory_id=factory and a.item_id=item.id),0),0);
    else raise exception 'aps_demand_ineligible' using errcode='22023';
    end if;
    if amount>eligible then raise exception 'aps_quantity_exceeds_demand' using errcode='22023';end if;

    links:=links||jsonb_build_array(jsonb_build_object(
      'factory_id',factory,'parent_order_id',parent,'source_item_id',item.id,'source_request_id',source_request.id,
      'sales_line_id',source_request.sales_order_line_id,'sales_order_id',sales_id,'purpose',source_request.request_type,
      'proposed_quantity',amount,'eligible_quantity_at_creation',eligible,'demand_quantity_at_creation',demand_quantity,
      'undelivered_quantity_at_creation',undelivered,'requested_by_date',requested,'priority',source_request.priority,
      'demand_created_at',demand_created));
    total:=total+amount;
  end loop;

  evidence:=jsonb_build_object('product_fingerprint',private.product_configuration_fingerprint(factory,product.id),
    'route_mode',candidate_route.mode,'route_scope',candidate_route.scope,'route_revision',candidate_route.revision,
    'recipe_version',requirements->>'recipe_version',
    'recipe_content_hash',(select encode(sha256(convert_to(jsonb_agg(to_jsonb(b) order by b.id)::text,'UTF8')),'hex')
      from public.bom_items b where b.factory_id=factory and b.bom_id=recipe));
  insert into private.aps_combined_order_drafts(factory_id,parent_order_id,product_id,recipe_id,candidate_line_id,unit,
    total_quantity,intent,manufacturing_evidence,created_by)
  values(factory,parent,product.id,recipe,candidate_line,product.stock_unit,total,intent,evidence,auth.uid());
  insert into private.aps_combined_demand_links
    select * from jsonb_populate_recordset(null::private.aps_combined_demand_links,links);
  return public.aps_combined_order_draft(factory,parent);
end $$;

revoke all on function private.aps_combined_require_view(uuid),
  public.aps_combined_order_draft(uuid,uuid),public.aps_create_combined_order_draft(uuid,uuid,uuid,jsonb)
  from public,anon,authenticated,service_role;
grant execute on function public.aps_combined_order_draft(uuid,uuid),
  public.aps_create_combined_order_draft(uuid,uuid,uuid,jsonb) to authenticated;

commit;
