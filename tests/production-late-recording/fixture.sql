do $$begin if current_database()<>'factory_lean_quality_local' or inet_server_addr()<>'127.0.0.1'::inet then raise exception 'Local M2 only';end if;end$$;
create schema late_test;
create table late_test.context(x jsonb);
create table late_test.checks(label text);
create function late_test.ok(v boolean,label text) returns void language plpgsql as $$begin if v is distinct from true then raise exception 'FAIL %',label;end if;insert into late_test.checks values(label);end$$;
create function late_test.fails(sql text,expected text) returns void language plpgsql as $$begin
 begin execute sql;exception when others then if sqlerrm=expected or sqlstate=expected then insert into late_test.checks values('rejected: '||expected);return;else raise;end if;end;
 raise exception 'Expected rejection: %',expected;end$$;
do $$declare x jsonb;f uuid;s timestamptz;sid uuid;begin
 x:=mp_test.fixture('m2');f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'M2 local','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 s:=clock_timestamp()+interval '.3 seconds';
 sid:=public.configure_production_shift(f,'M2 current','وردية محلية',s::time,(s+interval '4 hours')::time);
 perform pg_sleep(.4);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 insert into late_test.context values(x||jsonb_build_object('shift',sid));
end$$;
create function late_test.payload(x jsonb,q numeric default 2) returns jsonb language plpgsql as $$
declare p jsonb;w jsonb;m uuid;begin
 p:=public.production_shift_work((x->>'factory')::uuid,null,100);
 select value into w from jsonb_array_elements(p->'rows') where value->>'item_id'=x->>'item';
 select id into m from public.memberships where factory_id=(x->>'factory')::uuid and user_id=(x->>'owner')::uuid;
 return jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',m,'good',q,'discarded_quantity',0,'scrap_kg',0,
 'recording_context',jsonb_build_object('version',3,'execution_key',w->>'execution_key','occurrence_key',p#>>'{occurrence,occurrence_key}',
 'context_hash',w->>'context_hash','current_shift_quantity_confirmed',true));end$$;
create function late_test.new_context(label text,lifetime numeric default 30,completed boolean default true) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;s timestamptz;sid uuid;begin
 x:=mp_test.fixture(label);f:=(x->>'factory')::uuid;
 perform public.update_settings(f,'M2 race fixture','UTC',null);
 perform public.configure_working_calendar(f,127,'00:00','23:59');
 perform public.configure_center_capabilities(f,(x->>'machine')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',6000,'rate_unit','meter','setup_minutes',0)));
 s:=clock_timestamp()+interval '.2 seconds';
 sid:=public.configure_production_shift(f,'M2 race','محلي',s::time,(s+lifetime*interval '1 second')::time);
 perform pg_sleep(.3);
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,date_trunc('day',clock_timestamp())+interval '2 days 1 hour');
 perform public.start_product_item(f,(x->>'item')::uuid);
 if completed then perform public.finish_product_item(f,(x->>'item')::uuid);end if;
 return x||jsonb_build_object('shift',sid);end$$;
