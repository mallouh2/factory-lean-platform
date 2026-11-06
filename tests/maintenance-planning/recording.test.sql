begin;
create temporary table assertions(label text);
create function pg_temp.ok(value boolean,label text) returns void language plpgsql as $$begin
 if value is distinct from true then raise exception 'MP recording assertion failed: %',label;end if;insert into assertions values(label);
end$$;
create function pg_temp.fails(statement text,message text) returns void language plpgsql as $$begin
 begin execute statement;exception when others then if sqlerrm=message then insert into assertions values(message);return;end if;raise exception 'Expected %, got %',message,sqlerrm;end;
 raise exception 'Expected rejection %',message;
end$$;
do $$declare x jsonb;f uuid;r uuid;sid uuid;member uuid;e uuid;lot uuid;start_at timestamptz;p jsonb;digest text;begin
 x:=mp_test.fixture('wip');f:=(x->>'factory')::uuid;
 select id into member from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid;
 perform public.configure_center_capabilities(f,(x->>'independent')::uuid,jsonb_build_array(jsonb_build_object('product_id',x->>'product','rate',100,'rate_unit','meter','setup_minutes',0)));
 perform public.plan_product_item(f,(x->>'item')::uuid,(x->>'line')::uuid,clock_timestamp()+interval '2 hours');
 perform public.start_product_item(f,(x->>'item')::uuid);
 e:=(public.record_lean_production(f,jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',x->>'item','technician',member,'good',1,'discarded_quantity',0,'scrap_kg',0,'unfinished',2,'remaining_work','Finish on independent equipment','input_quantity',0),gen_random_uuid())->>'id')::uuid;
 perform public.finish_product_item(f,(x->>'item')::uuid);
 select id into lot from public.unfinished_lots where source_entry_id=e;
 update private.maintenance_planning_activation set enabled=true;
 r:=public.create_maintenance_request(f,jsonb_build_object('work_center_id',x->>'independent','title','Independent hold','priority','NORMAL','maintenance_kind','PLANNED','estimated_duration_minutes',1,'assigned_to',x->>'worker'),gen_random_uuid());
 start_at:=clock_timestamp()+interval '1 second';sid:=mp_test.plan(x||jsonb_build_object('request',r),start_at,start_at+interval '2 minutes');perform mp_test.command(f,r,'confirm','{}',1,gen_random_uuid());perform pg_sleep(1.1);
 perform public.change_maintenance_request(f,r,'start','{}',2,gen_random_uuid());
 select md5(jsonb_agg(to_jsonb(l) order by l.id)::text) into digest from public.unfinished_lots l where l.factory_id=f;
 p:=jsonb_build_object('unit_kind','machine','production_unit',x->>'independent','item',x->>'item','technician',member,'good',1,'discarded_quantity',0,'scrap_kg',0,'unfinished',0,'remaining_work','','input_lot',lot,'input_quantity',1);
 perform pg_temp.fails(format('select public.record_lean_production(%L,%L,gen_random_uuid())',f,p),'maintenance_capacity_reserved');
 perform pg_temp.ok((select md5(jsonb_agg(to_jsonb(l) order by l.id)::text)=digest from public.unfinished_lots l where l.factory_id=f),'blocked reprocessing preserves WIP');
 perform pg_temp.ok((select count(*)=1 from public.production_entries where factory_id=f),'blocked reprocessing creates no duplicate Good');
 perform pg_temp.ok((select on_hand=1 from public.finished_goods_balances where factory_id=f and product_id=(x->>'product')::uuid),'finished balance conserved');
 perform public.change_maintenance_request(f,r,'complete','{"work_note":"Hold test finished"}',3,gen_random_uuid());
 perform pg_temp.ok((select released_at is null from public.maintenance_schedules where id=sid),'recording remains protected awaiting verification');
end$$;
select count(*)||' Maintenance recording assertions passed' from assertions;
rollback;
