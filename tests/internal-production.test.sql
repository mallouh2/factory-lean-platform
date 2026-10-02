-- TESTING only: fixtures and permission probes are rolled back.
begin;
create function pg_temp.internal_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'Internal Production: %',label;end if;end$$;
create function pg_temp.internal_error(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=expected then return;end if;raise exception 'expected %, got %',expected,sqlerrm;end;
 raise exception 'expected % but succeeded',expected;end$$;
do $test$
declare f uuid:='bab9b5da-d78d-4be7-b6d4-bb6afc388c3a';actor uuid:='d699a3ac-fab0-4faf-b958-f3902bc357ba';p uuid;r uuid;i uuid;
 legacy jsonb;items jsonb;statement text;created timestamptz:=clock_timestamp();
begin
 perform set_config('request.jwt.claim.sub',actor::text,true);
 select id into p from public.products where factory_id=f limit 1;
 select jsonb_agg(to_jsonb(x) order by id) into legacy from public.production_requests x;
 items:=jsonb_build_array(jsonb_build_object('product_id',p,'quantity',7,'unit','meter'));
 statement:=format('select public.create_production_request(%L,%L,%L,null,%%L,%L)',f,'Internal QA','normal',items);
 perform pg_temp.internal_error(format(statement,''),'internal_reason_required');
 perform pg_temp.internal_error(format(statement,E' \t\n '),'internal_reason_required');
 perform pg_temp.internal_error(format(statement,repeat('x',2001)),'invalid_notes');
 r:=public.create_production_request(f,'Internal QA','normal',null,'  Engineering trial  ',items);
 perform pg_temp.internal_assert((select request_type='INTERNAL_PRODUCTION' and notes='Engineering trial' and requested_by=actor
  and requested_by_name=(select display_name from public.memberships where factory_id=f and user_id=actor)
  and created_at>=created and sales_order_line_id is null from public.production_requests where id=r),'server origin/reason/actor/time');
 select id into i from public.production_orders where request_id=r;
 perform pg_temp.internal_assert((select status='planned' and line_id is null and start_time is null and expected_finish is null
  and actual_start is null and actual_finish is null and target_quantity=7 and unit='meter' from public.production_orders where id=i),'unscheduled Planning demand');
 perform pg_temp.internal_assert(not has_table_privilege('authenticated','public.production_requests','INSERT'),'no direct header creation');
 perform pg_temp.internal_assert(not has_function_privilege('authenticated','private.fulfillment_production(uuid,uuid,text,numeric,text,uuid,timestamptz)','EXECUTE'),'automatic helper inaccessible');
 perform pg_temp.internal_assert(not has_function_privilege('authenticated','private.create_production_request(uuid,text,text,timestamptz,text,jsonb)','EXECUTE'),'private creation inaccessible');
 perform pg_temp.internal_assert(not exists(select 1 from public.sales_incoming_allocations where item_id=i),'no Sales allocation');
 perform pg_temp.internal_assert((select count(*) from public.production_requests)=jsonb_array_length(legacy)+1,'no fabricated replenishment demand');
 perform pg_temp.internal_error(format('select public.create_production_request(%L,%L,%L,null,%L,%L)',f,'Invalid product','normal','Trial',
  jsonb_build_array(jsonb_build_object('product_id',gen_random_uuid(),'quantity',7,'unit','meter'))),'invalid_request_product');
 perform pg_temp.internal_error(format('select public.create_production_request(%L,%L,%L,null,%L,%L)',f,'Invalid unit','normal','Trial',
  jsonb_build_array(jsonb_build_object('product_id',p,'quantity',7,'unit','unit'))),'invalid_request_unit');
 perform pg_temp.internal_error(format('select public.create_production_request(%L,%L,%L,null,%L,%L)',f,'Invalid quantity','normal','Trial',
  jsonb_build_array(jsonb_build_object('product_id',p,'quantity',0,'unit','meter'))),'invalid_request_quantity');
 perform pg_temp.internal_error(format('select public.create_production_request(%L,%L,%L,null,%L,%L)',gen_random_uuid(),'Wrong factory','normal','Trial',items),'permission_denied');
 perform pg_temp.internal_error(format('update public.production_requests set request_type=%L where id=%L','SALES_PRODUCTION',r),'request_origin_immutable');
 perform pg_temp.internal_error(format('update public.production_requests set request_type=%L where id=%L','STOCK_REPLENISHMENT',r),'request_origin_immutable');
 perform pg_temp.internal_error(format('update public.production_requests set requested_by=%L where id=%L',gen_random_uuid(),r),'request_origin_immutable');
 perform pg_temp.internal_error(format('update public.production_requests set notes=%L where id=%L','Changed reason',r),'request_origin_immutable');
 perform pg_temp.internal_assert((select jsonb_agg(to_jsonb(x) order by id) from public.production_requests x where id<>r)=legacy,'legacy unchanged');
 perform pg_temp.internal_assert(exists(select 1 from public.audit_logs where entity_id=r),'normal header audit');
 delete from public.user_permissions where factory_id=f and user_id=actor and module='orders' and action='create';
 perform pg_temp.internal_error(format(statement,'Engineering trial'),'permission_denied');
end$test$;
select 'Internal Production assertions passed' as result;
rollback;
