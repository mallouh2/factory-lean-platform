do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Disposable localhost only';end if;end$$;
create schema output_test;
create table output_test.checks(label text);
create function output_test.ok(v boolean,label text) returns void language plpgsql as $$begin
 if v is distinct from true then raise exception 'FAIL %',label;end if;insert into output_test.checks values(label);
end$$;
create function output_test.fails(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if sqlerrm=expected or sqlstate=expected then insert into output_test.checks values('denied: '||expected);return;else raise;end if;end;
 raise exception 'Expected failure %',expected;
end$$;

-- FIXTURE ADAPTER ONLY: simulate the future deferred-credit recorder by disabling
-- ONLY the legacy immediate-credit trigger during fixture creation. Every other
-- recording/Quality/KG constraint stays enabled. No migration or active app uses
-- this adapter. This is NOT proof of the future recording integration.
create function output_test.fixture(label text,good numeric default 100,wip numeric default 0) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;entry uuid;tech uuid;step1 uuid;step2 uuid;g1 uuid:=gen_random_uuid();g2 uuid:=gen_random_uuid();g3 uuid:=gen_random_uuid();groups jsonb:='[]';r jsonb;begin
 x:=mp_test.fixture(label);f:=(x->>'factory')::uuid;
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 select id into tech from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid) returning id into step1;
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id) values(f,(x->>'product')::uuid,2,'work_center',(x->>'other_machine')::uuid) returning id into step2;
 alter table public.production_entries disable trigger finished_goods_receipt;
 r:=public.record_lean_production(f,jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',tech,
 'good',good,'discarded_quantity',0,'scrap_kg',0,'unfinished',wip,'remaining_work',case when wip>0 then 'Finish configured steps' else '' end,'input_quantity',0),gen_random_uuid());
 alter table public.production_entries enable trigger finished_goods_receipt;
 entry:=(r->>'id')::uuid;
 if good>0 then groups:=groups||jsonb_build_array(jsonb_build_object('id',g1,'quantity',good::text,'missing_operations','[]'::jsonb));end if;
 if wip>0 then
 groups:=groups||jsonb_build_array(jsonb_build_object('id',g2,'quantity',(wip*.6)::text,'missing_operations',jsonb_build_array(step1)),jsonb_build_object('id',g3,'quantity',(wip*.4)::text,'missing_operations',jsonb_build_array(step2,step1)));
 end if;
 r:=private.manufactured_output_command(f,'DECLARE',entry,jsonb_build_object('groups',groups),0,gen_random_uuid());
 return x||jsonb_build_object('entry',entry,'output',r->>'output_id','g1',g1,'g2',g2,'g3',g3,'step1',step1,'step2',step2,'groups',r->'groups');
end$$;
-- Test-only facade lets real authenticated roles exercise the internal SQL
-- authorization, without granting direct private table/function privileges.
create function output_test.command(f uuid,op text,t uuid,p jsonb,r bigint,k uuid) returns jsonb language sql security definer set search_path='' as $$
 select private.manufactured_output_command(f,op,t,p,r,k)
$$;
-- Test-only posting adapter: the actual ledger/source triggers run unmodified.
-- Factory/structure lock, original UUID recovery, posting + binding are atomic.
-- No Sales integration is claimed by this fixture.
create function output_test.receive(x jsonb,g uuid,q numeric,rev bigint,k uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare f uuid:=(x->>'factory')::uuid;m uuid;r jsonb;old private.manufactured_output_events;begin
 perform private.manufactured_output_authorize(f,'RECEIPT',rev);
 perform pg_advisory_xact_lock(hashtextextended(f::text,0));perform pg_advisory_xact_lock(hashtextextended(f::text||':structure',0));
 perform private.manufactured_output_authorize(f,'RECEIPT',rev);
 select * into old from private.manufactured_output_events where factory_id=f and request_id=k;
 if found then
  if old.result->>'group_id'<>g::text or (old.result->>'quantity')::numeric<>q then raise exception 'request_conflict';end if;
  return private.manufactured_output_command(f,'RECEIPT',(x->>'output')::uuid,old.intent->'payload',rev,k);
 end if;
 perform private.finished_balance(f,(x->>'product')::uuid,'meter');
 update public.finished_goods_balances set on_hand=on_hand+q where factory_id=f and product_id=(x->>'product')::uuid and unit='meter';
 insert into public.finished_goods_movements(factory_id,product_id,unit,kind,stock_delta,entry_id,created_by)
 values(f,(x->>'product')::uuid,'meter','production_receipt',q,(x->>'entry')::uuid,auth.uid()) returning id into m;
 r:=private.manufactured_output_command(f,'RECEIPT',(x->>'output')::uuid,jsonb_build_object('group_id',g,'quantity',q::text,'movement_id',m,'physical_confirmation',true,'location','Test receiving bay'),rev,k);
 set constraints all immediate;set constraints all deferred;
 return r;
end$$;
grant usage on schema output_test to authenticated;
revoke all on all functions in schema output_test from public,anon,authenticated;
grant execute on function output_test.command(uuid,text,uuid,jsonb,bigint,uuid),output_test.receive(jsonb,uuid,numeric,bigint,uuid) to authenticated;
