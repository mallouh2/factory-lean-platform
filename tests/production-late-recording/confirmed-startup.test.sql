-- Run on the canonical local preview with ON_ERROR_STOP=1. All fixtures roll back.

begin;
set local statement_timeout = '5s';
do $guard$
begin
 if inet_server_addr() <> '127.0.0.1'::inet or inet_server_port() <> 29719
   or current_database() <> 'factory_lean_quality_local'
   or lower(replace(current_setting('data_directory'),chr(92),'/')) <> 'd:/factorylean/preview/review-20261108/data' then
   raise exception 'unexpected local backend identity';
 end if;
end $guard$;

set local lock_timeout='3s';
set local statement_timeout='15s';

create function pg_temp.g6_assert(ok boolean,note text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Group 6A check failed: %',note; end if; end $$;

create function pg_temp.g6_payload(f uuid,i uuid,l uuid,m uuid,q numeric,total numeric,startkg numeric,start_id uuid,start_at timestamptz)
returns jsonb language plpgsql as $$
declare w jsonb; ctx jsonb;
begin
 ctx:=public.production_shift_work(f,null,100);
 select value into w from jsonb_array_elements(ctx->'rows') where value->>'item_id'=i::text;
 perform pg_temp.g6_assert(w is not null,'real current-shift work');
 return jsonb_build_object('unit_kind','line','production_unit',l,'item',i,'technician',m,
  'good',q,'scrap_kg',total,'startup_kg',startkg,'discarded_quantity',0,'startup_id',start_id,'startup_at',start_at,
  'output_groups',jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',q::text,'missing_operations','[]'::jsonb)),
  'recording_context',jsonb_build_object('version',3,'execution_key',w->>'execution_key','occurrence_key',ctx#>>'{occurrence,occurrence_key}',
    'context_hash',w->>'context_hash','current_shift_quantity_confirmed',true));
end $$;

create temporary table g6_startup_proof (f uuid,i uuid);
do $$
declare x jsonb; f uuid; i uuid; l uuid; product uuid; actor uuid; tech uuid; material uuid; recipe uuid;
 start_id uuid:=gen_random_uuid(); other_start uuid:=gen_random_uuid(); request uuid:=gen_random_uuid();
 start_at timestamptz; current_mark timestamptz;
 p jsonb; a jsonb; b jsonb; c jsonb; replay jsonb; quality_row private.manufactured_outputs; quality_groups jsonb; released jsonb; receiving jsonb; received jsonb; warehouse uuid; receipt_request uuid:=gen_random_uuid();
begin
 x:=mp_test.fixture('group6a-stock-'||gen_random_uuid()::text); f:=(x->>'factory')::uuid; i:=(x->>'item')::uuid;
 l:=(x->>'line')::uuid; product:=(x->>'product')::uuid; actor:=(x->>'owner')::uuid;
 perform public.update_settings(f,'Group 6A rollback QA','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 current_mark:=clock_timestamp()+interval '1 second';
 perform public.configure_production_shift(f,'QA current','QA current',(current_mark at time zone 'UTC')::time,((current_mark+interval '4 hours') at time zone 'UTC')::time);
 perform pg_sleep(1.1);
 select id into tech from public.memberships where factory_id=f and user_id=actor;
 insert into public.materials(factory_id,name,code,unit,inventory_kind) values(f,'Synthetic resin','G6A-RESIN','kg','RAW_MATERIAL') returning id into material;
 insert into public.bom_versions(factory_id,product_id,version,batch_quantity,output_unit,created_by)
  values(f,product,1,1,'kg',actor) returning id into recipe;
 insert into public.bom_items(factory_id,bom_id,material_id,quantity,unit)
  values(f,recipe,material,1,'kg');
 insert into private.production_input_routes(factory_id,product_id,mode,scope,updated_by)
  values(f,product,'DIRECT_RAW','00000000-0000-0000-0000-000000000000',actor);
 insert into private.production_material_policy(factory_id,seconds,stock_enabled,stock_activated_at)
  values(f,21600,true,clock_timestamp()-interval '1 hour');
 insert into private.production_stock_movements(factory_id,material_id,quantity,kind,reference,evidence,actor)
  values(f,material,100,'DELIVERY',gen_random_uuid(),'{"rollback_fixture":true}',actor);
 perform public.plan_product_item(f,i,l,clock_timestamp()+interval '2 minutes');
 perform private.set_manufactured_output_activation(f,true,0,'Group 6A rollback-only QA');
 perform public.start_product_item(f,i);
 select actual_start into start_at from public.production_orders where factory_id=f and id=i;

 insert into g6_startup_proof values(f,i);
 p:=pg_temp.g6_payload(f,i,l,tech,2,3,1,start_id,start_at);
 a:=public.record_manufactured_output(f,p,request);
 replay:=public.record_manufactured_output(f,p,request);
 perform pg_temp.g6_assert(a->>'entry_id'=replay->>'entry_id','same request retains one entry');
 b:=public.record_manufactured_output(f,pg_temp.g6_payload(f,i,l,tech,2,4,2,other_start,start_at),gen_random_uuid());
 c:=public.record_manufactured_output(f,pg_temp.g6_payload(f,i,l,tech,2,1,0,null,null),gen_random_uuid());
 begin
  perform public.record_manufactured_output(f,pg_temp.g6_payload(f,i,l,tech,2,1,1.01,start_id,start_at),gen_random_uuid());
  raise exception 'Greater than total was accepted';
 exception when sqlstate '22023' then perform pg_temp.g6_assert(sqlerrm='lean_invalid','specific invalid startup check'); end;
 begin
  perform public.record_manufactured_output(f,pg_temp.g6_payload(f,i,l,tech,2,1,.5,null,null),gen_random_uuid());
  raise exception 'Unassociated startup scrap accepted';
 exception when sqlstate '22023' then perform pg_temp.g6_assert(sqlerrm='lean_startup_required','requires startup ID'); end;
 perform pg_temp.g6_assert((select count(*)=3 and sum(effective_scrap_kg)=8 and sum(effective_startup_kg)=3
  and count(*) filter(where lean_startup_id=start_id)=2 and count(*) filter(where lean_startup_id is null)=1
  from public.production_entries where factory_id=f and order_id=i),'shared startup and zero-startup evidence');
 perform pg_temp.g6_assert((select count(*)=1 from public.lean_startups where factory_id=f),'same timestamp with different IDs resolves to the original event');
 perform pg_temp.g6_assert((select s.line_id=l and s.product_id=product and s.item_id=i and r.id=s.execution_run_id
   from public.lean_startups s join private.production_execution_runs r on r.id=s.execution_run_id
   where s.factory_id=f and s.id=start_id),'actual line, product and execution association');
 begin
  perform public.record_manufactured_output(f,pg_temp.g6_payload(f,i,l,tech,2,1,.5,gen_random_uuid(),start_at-interval '2 seconds'),gen_random_uuid());
  raise exception 'Startup predating actual execution accepted';
 exception when sqlstate '22023' then perform pg_temp.g6_assert(sqlerrm in('lean_startup_execution','lean_invalid'),'historical or wrong run start rejected'); end;
 perform pg_temp.g6_assert((select count(*)=3 and sum(quantity)=11 from private.production_stock_consumption where factory_id=f),'Good weight plus total scrap, once per entry');
 perform pg_temp.g6_assert(private.production_stock_quantity(f,material)=89,'physical Production Stock balance');
 perform pg_temp.g6_assert((select count(*)=0 from public.inventory_transactions where factory_id=f and material_id=material),'no second Warehouse debit');
 perform pg_temp.g6_assert(not exists(select from public.finished_goods_balances where factory_id=f and product_id=product),'no finished stock before Quality and Warehouse receipt');

 select * into quality_row from private.manufactured_outputs where factory_id=f and entry_id=(a->>'entry_id')::uuid;
 select jsonb_agg(value||jsonb_build_object('released',value->>'quantity')) into quality_groups from jsonb_array_elements(quality_row.recorded_groups);
 released:=public.manufactured_output_command(f,'QUALITY',quality_row.id,jsonb_build_object('groups',quality_groups,'rejected','0','reason','Inspected in rollback fixture'),1,gen_random_uuid());
 perform pg_temp.g6_assert(not exists(select from public.finished_goods_movements where factory_id=f),'Quality does not create stock');
 perform public.factory_warehouse_command(f,'DEFAULTS',null,'{}',null,gen_random_uuid());
 select id into warehouse from public.factory_warehouses where factory_id=f and storage_class='FINISHED' limit 1;
 perform pg_temp.g6_assert(warehouse is not null,'existing finished warehouse fixture');
 receiving:=jsonb_build_object('group_id',quality_groups->0->>'id','quantity','2','warehouse_id',warehouse,'physical_confirmation',true,'note','Controlled rollback receipt');
 received:=public.receive_manufactured_output(f,quality_row.id,receiving,(released->>'revision')::bigint,receipt_request);
 perform pg_temp.g6_assert(received=public.receive_manufactured_output(f,quality_row.id,receiving,(released->>'revision')::bigint,receipt_request),'Warehouse receipt replay');
 perform pg_temp.g6_assert((select count(*)=1 and sum(stock_delta)=2 from public.finished_goods_movements where factory_id=f),'only one confirmed finished stock posting');
 perform pg_temp.g6_assert(private.production_stock_quantity(f,material)=89,'Quality and Warehouse do not consume raw material twice');
 raise notice 'PASS Quality release and Warehouse receipt/replay preserve actual scrap classification and raw-stock balance';
 raise notice 'PASS startup scrap: three manufactured entries, 8 kg total incl. 3 kg startup, 11 kg actual consumption, immutable retry, invalid input rejected';
end $$;
select pg_temp.g6_assert(jsonb_array_length(public.lean_read(f,jsonb_build_object('mode','recording_context','item_id',i))->'startup_windows')=1,'reader exposes verified actual startup window') from g6_startup_proof;
rollback;
