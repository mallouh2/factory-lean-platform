-- Run only after the Phase 1A migration has been approved for the canonical preview.
-- Synthetic factory, memberships and commands are scoped to this rolled-back transaction.
begin;
set local statement_timeout='30s';
set local lock_timeout='5s';

do $guard$
begin
  if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>29719
    or current_database()<>'factory_lean_quality_local'
    or lower(replace(current_setting('data_directory'),chr(92),'/'))<>'d:/factorylean/preview/review-20261108/data'
  then raise exception 'Unexpected local database';end if;
end $guard$;

create function pg_temp.combined_assert(result boolean, message text) returns void language plpgsql as $$
begin
  if result is distinct from true then raise exception '%',message;end if;
end $$;

create function pg_temp.combined_reject(f uuid,l uuid,demands jsonb,expected text) returns void language plpgsql as $$
begin
  perform public.aps_create_combined_order_draft(f,gen_random_uuid(),l,demands);
  raise exception 'Expected rejection %',expected;
exception when others then
  if sqlerrm<>expected then raise;end if;
end $$;

create function pg_temp.combined_sale(f uuid,p uuid, due timestamptz,customer text) returns uuid
language plpgsql as $$
declare sale uuid; source uuid;
begin
  sale:=public.create_sales_order(f,jsonb_build_object('customer_reference',customer,'requested_delivery',due,
    'lines',jsonb_build_array(jsonb_build_object('product_id',p,'quantity',30,'unit','meter'))),gen_random_uuid());
  perform public.approve_sales_order(f,sale,gen_random_uuid());
  select o.id into strict source from public.production_orders o
  join public.production_requests r on r.factory_id=f and r.id=o.request_id
  join public.sales_order_lines l on l.factory_id=f and l.id=r.sales_order_line_id
  where o.factory_id=f and o.product_id=p and l.order_id=sale;
  return source;
end $$;

create function pg_temp.combined_link(i uuid,r uuid,q text) returns jsonb
language sql immutable as $$select jsonb_build_object('source_item_id',i,'recipe_id',r,'quantity',q)$$;

do $scenario$
declare
  x jsonb; f uuid; a uuid; viewer uuid; p uuid; other_product uuid; l uuid; m uuid; standalone uuid;
  recipe uuid; stale_recipe uuid; other_recipe uuid; resin uuid; stock_request uuid; stock_item uuid;
  dated_early uuid; dated_late uuid; undated uuid; customer_for_stock uuid; different_product uuid;
  dated_early_due timestamptz:=date_trunc('minute',clock_timestamp())+interval '2 days';
  dated_late_due timestamptz:=dated_early_due+interval '1 day';
  input jsonb; draft jsonb; mixed jsonb; parent uuid:=gen_random_uuid(); stock_level numeric;
  before_evidence jsonb; after_evidence jsonb;
begin
  x:=mp_test.fixture('aps-1a-'||gen_random_uuid());
  f:=(x->>'factory')::uuid; a:=(x->>'owner')::uuid; viewer:=(x->>'viewer')::uuid;
  p:=(x->>'product')::uuid; l:=(x->>'line')::uuid; m:=(x->>'machine')::uuid; standalone:=(x->>'item')::uuid;
  perform public.update_settings(f,'Phase 1A rollback fixture','UTC',null);
  perform public.configure_working_calendar(f,127,'00:00','23:59');
  insert into public.materials(factory_id,name,code,unit,inventory_kind)
    values(f,'Synthetic pipe resin','APS-R','kg','RAW_MATERIAL') returning id into resin;
  insert into public.products(factory_id,name,code,unit,stock_unit,unit_weight_kg)
    values(f,'Pipe with a different cut specification','APS-OTHER','meter','meter',.5) returning id into other_product;
  insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)
    values(f,m,other_product,100,'meter',5);
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)
    values(f,p,1,1,'kg',a) returning id into stale_recipe;
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)
    values(f,p,2,1,'kg',a) returning id into recipe;
  insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)
    values(f,other_product,1,1,'kg',a) returning id into other_recipe;
  insert into public.bom_items(factory_id,bom_id,material_id,quantity,unit)
    values(f,recipe,resin,1,'kg'),(f,stale_recipe,resin,.95,'kg'),(f,other_recipe,resin,1,'kg');
  insert into private.production_input_routes(factory_id,product_id,mode,scope,updated_by)
    values(f,p,'DIRECT_RAW','00000000-0000-0000-0000-000000000000',a),
          (f,other_product,'DIRECT_RAW','00000000-0000-0000-0000-000000000000',a);

  dated_late:=pg_temp.combined_sale(f,p,dated_late_due,'Later customer');
  undated:=pg_temp.combined_sale(f,p,null,'Undated customer');
  dated_early:=pg_temp.combined_sale(f,p,dated_early_due,'Earlier customer');
  customer_for_stock:=pg_temp.combined_sale(f,p,dated_late_due,'Customer paired with replenishment');
  different_product:=pg_temp.combined_sale(f,other_product,dated_early_due,'Different pipe');
  perform public.configure_product_stock(f,p,'MAKE_TO_STOCK','meter',1000,2000);
  stock_level:=private.projected_finished(f,p,'meter')+private.purchase_incoming(f,p,'meter');
  stock_request:=public.confirm_warehouse_replenishment(f,p,'produce','meter',stock_level,2000-stock_level,gen_random_uuid());
  select o.id into strict stock_item from public.production_orders o where o.factory_id=f and o.request_id=stock_request;

  select jsonb_build_array(
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_orders t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_requests t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_orders t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_order_lines t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_incoming_allocations t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.finished_goods_movements t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_plan_revisions t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from private.production_execution_runs t where factory_id=f)
  ) into before_evidence;
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'10'),pg_temp.combined_link(different_product,other_recipe,'5')),
    'aps_product_or_unit_mismatch');
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'10'),pg_temp.combined_link(dated_late,stale_recipe,'5')),
    'aps_recipe_unverified_or_mismatched');
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'10'),pg_temp.combined_link(dated_early,recipe,'5')),
    'aps_duplicate_demand');
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'31'),pg_temp.combined_link(dated_late,recipe,'5')),
    'aps_quantity_exceeds_demand');
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'0'),pg_temp.combined_link(dated_late,recipe,'5')),
    'aps_quantity_invalid');

  input:=jsonb_build_array(pg_temp.combined_link(undated,recipe,'3'),
    pg_temp.combined_link(dated_late,recipe,'8'),pg_temp.combined_link(dated_early,recipe,'10.5'));
  draft:=public.aps_create_combined_order_draft(f,parent,l,input);
  perform pg_temp.combined_assert(draft=public.aps_create_combined_order_draft(f,parent,l,input),'Exact retry did not recover the draft');
  perform pg_temp.combined_assert(draft->>'parent_order_id'=parent::text and (draft->>'total_quantity')::numeric=21.5
    and draft->>'operational'='false' and draft->>'recipe_id'=recipe::text,'Parent identity, recipe or total incorrect');
  perform pg_temp.combined_assert(draft#>>'{demands,0,source_item_id}'=dated_early::text
    and (draft#>>'{demands,0,requested_by_date}')::timestamptz=dated_early_due
    and draft#>>'{demands,1,source_item_id}'=dated_late::text
    and (draft#>>'{demands,1,requested_by_date}')::timestamptz=dated_late_due
    and draft#>>'{demands,2,source_item_id}'=undated::text and draft#>>'{demands,2,sales_follow_up}'='true',
    'Individual deadlines or dated and undated precedence lost');
  perform pg_temp.combined_assert((draft#>>'{demands,0,demand_quantity_at_creation}')::numeric=30
    and (draft#>>'{demands,0,eligible_quantity_at_creation}')::numeric=30
    and (draft#>>'{demands,0,proposed_quantity}')::numeric=10.5,
    'Partial coverage was treated as full or changed original demand');
  perform pg_temp.combined_reject(f,l,jsonb_build_array(
    pg_temp.combined_link(dated_early,recipe,'10'),pg_temp.combined_link(stock_item,recipe,'5')),
    'aps_duplicate_demand');

  mixed:=public.aps_create_combined_order_draft(f,gen_random_uuid(),l,jsonb_build_array(
    pg_temp.combined_link(stock_item,recipe,'10'),pg_temp.combined_link(customer_for_stock,recipe,'5')));
  perform pg_temp.combined_assert((mixed->>'total_quantity')::numeric=15
    and mixed#>>'{demands,0,purpose}'='SALES_PRODUCTION' and mixed#>>'{demands,1,purpose}'='STOCK_REPLENISHMENT',
    'Customer and confirmed replenishment lineage or priority incorrect');

  perform set_config('request.jwt.claim.sub',viewer::text,true);
  begin
    perform public.aps_combined_order_draft(f,parent);
    raise exception 'Unauthorized reader permitted';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.aps_create_combined_order_draft(f,gen_random_uuid(),l,input);
    raise exception 'Unauthorized writer permitted';
  exception when insufficient_privilege then null;
  end;
  perform set_config('request.jwt.claim.sub',a::text,true);
  select jsonb_build_array(
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_orders t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_requests t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_orders t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_order_lines t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.sales_incoming_allocations t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.finished_goods_movements t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from public.production_plan_revisions t where factory_id=f),
    (select jsonb_agg(to_jsonb(t) order by t.id) from private.production_execution_runs t where factory_id=f)
  ) into after_evidence;
  perform pg_temp.combined_assert(before_evidence=after_evidence,'Draft wrote to an operational table');
  perform pg_temp.combined_assert(not exists(select from public.production_entries where factory_id=f)
    and not exists(select from public.inventory_transactions where factory_id=f)
    and not exists(select from private.production_stock_consumption where factory_id=f),
    'Draft generated production or stock entries');
  begin
    perform public.plan_product_item(f,parent,l,clock_timestamp()+interval '10 minutes');
    raise exception 'Draft could be scheduled as an operational order';
  exception when others then
    if sqlerrm<>'not_found' then raise;end if;
  end;
  begin
    perform public.start_product_item(f,parent);
    raise exception 'Draft could start as an operational order';
  exception when others then
    if sqlerrm<>'not_found' then raise;end if;
  end;
  perform public.plan_product_item(f,standalone,l,clock_timestamp()+interval '10 minutes');
  perform pg_temp.combined_assert(exists(select from public.production_plan_revisions where factory_id=f and item_id=standalone),
    'Existing standalone planning stopped working');
  raise notice 'PASS combined lineage, ranking, partial coverage, eligibility, retries, permissions, unchanged ledger and standalone Planning';
end $scenario$;

rollback;
