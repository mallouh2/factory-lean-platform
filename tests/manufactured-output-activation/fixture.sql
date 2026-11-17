-- Prerequisites: unchanged mp_test.fixture and late_test context/payload helpers.
-- Installed only by the explicitly guarded disposable acceptance runner.
create schema activation_test;
create table activation_test.contexts(label text primary key,x jsonb not null);
create table activation_test.checks(label text not null);
create table activation_test.requests(label text primary key,command text,args jsonb,result jsonb);
grant usage on schema activation_test to authenticated;
grant usage on schema late_test to authenticated;
grant all on activation_test.checks,activation_test.requests to authenticated;
grant select on activation_test.contexts to authenticated;
create function activation_test.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'Activation assertion: %',label;end if;
 insert into activation_test.checks values(label);
end$$;
create function activation_test.reject(statement text,expected text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then
 if sqlerrm=expected or sqlstate=expected then perform activation_test.ok(true,'Rejected: '||expected);return;end if;
 raise exception 'Expected %, got %: %',expected,sqlstate,sqlerrm;end;
 raise exception 'Expected rejection: %',expected;
end$$;
create function activation_test.new_context(label text) returns jsonb language plpgsql as $$
declare x jsonb;f uuid;step uuid;begin
 x:=late_test.new_context('activation-'||label,28800,false);f:=(x->>'factory')::uuid;
 perform set_config('request.jwt.claim.sub',x->>'owner',true);
 insert into public.production_routing_steps(factory_id,product_id,position,kind,work_center_id)
 values(f,(x->>'product')::uuid,1,'work_center',(x->>'machine')::uuid) returning id into step;
 insert into public.user_permissions(factory_id,user_id,module,action)
 select f,(x->>'worker')::uuid,'quality',a from unnest(array['view','create','edit'])a;
 insert into public.user_permissions(factory_id,user_id,module,action)
 select f,(x->>'viewer')::uuid,'warehouse',a from unnest(array['view','edit','issue'])a;
 perform public.factory_warehouse_command(f,'DEFAULTS',null,'{}',null,gen_random_uuid());
 x:=x||jsonb_build_object('step',step,'finished_warehouse',(select id from public.factory_warehouses where factory_id=f and storage_class='FINISHED'),
 'unfinished_warehouse',(select id from public.factory_warehouses where factory_id=f and storage_class='SEMI_FINISHED'));
 insert into activation_test.contexts values(label,x);return x;
end$$;
create function activation_test.payload(x jsonb,g numeric default 90,w numeric default 10) returns jsonb language plpgsql as $$
begin
 return late_test.payload(x,g)||jsonb_build_object('confirm_overproduction',true,'scrap_kg',0,'unfinished',w,
 'remaining_work',case when w>0 then 'Printing remains'else''end,'output_groups',
 jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',g::text,'missing_operations','[]'::jsonb))||
 case when w>0 then jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'quantity',w::text,'missing_operations',jsonb_build_array(x->>'step')))else'[]'::jsonb end);
end$$;
select activation_test.new_context('main');
select activation_test.new_context('legacy');
select activation_test.new_context('foreign');
