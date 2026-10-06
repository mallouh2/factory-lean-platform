-- Explicit TESTING-only reset and fixture import. Not a migration.
-- Historical import is user-authorized. Every CHECK/FK/business trigger stays enabled.
begin;
__GUARD__
set local statement_timeout='120s';
select pg_advisory_xact_lock(hashtextextended('bab9b5da-d78d-4be7-b6d4-bb6afc388c3a:structure',0));
select set_config('request.jwt.claim.sub','d699a3ac-fab0-4faf-b958-f3902bc357ba',true);
create temp table demo_checks(label text) on commit drop;
create temp table demo_ids(code text primary key,id uuid not null) on commit drop;
create temp table demo_preserved(name text primary key,digest text) on commit drop;
create function pg_temp.assert_demo(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'DEMO invariant: %',label;end if;
 insert into demo_checks values(label);end$$;
create function pg_temp.f() returns uuid language sql as $$select 'bab9b5da-d78d-4be7-b6d4-bb6afc388c3a'::uuid$$;
create function pg_temp.actor() returns uuid language sql as $$select 'd699a3ac-fab0-4faf-b958-f3902bc357ba'::uuid$$;
create function pg_temp.lean_actor() returns uuid language sql as $$select 'c94a7c99-7833-51da-aa7c-1edd2592ce71'::uuid$$;
create function pg_temp.day() returns date language sql as $$select __DAY__::date$$;
create function pg_temp.id(c text) returns uuid language sql as $$select id from demo_ids where code=c$$;
create function pg_temp.put(c text,u uuid) returns uuid language plpgsql as $$begin
 insert into demo_ids values(c,u);return u;end$$;
create function pg_temp.config_digest(t text) returns text language plpgsql as $$declare result text;removed text[]:='{}';begin
 if t='factories' then removed:=array['structure_version'];
 elsif t='work_centers' then removed:=array['order_id','operator_id','status','updated_at','last_restart_time'];
 elsif t='production_lines' then removed:=array['paused_at','pause_reason'];end if;
 execute format('select md5(coalesce(string_agg((to_jsonb(x)-$1)::text,E''\n'' order by (to_jsonb(x)-$1)::text),'''')) from public.%I x',t) into result using removed;return result;end$$;
do $$declare t text;begin
 perform pg_temp.assert_demo(pg_temp.day()<=(clock_timestamp() at time zone 'Asia/Qatar')::date,'demo day is not in the future');
 foreach t in array array['machine_statuses','permissions','role_permissions','roles','support_access','areas','memberships',
 'work_center_alternatives','production_lines','user_permissions','work_centers','factories','downtime_reasons','production_shifts',
 'work_center_categories','permission_packages','permission_package_permissions','member_permission_packages'] loop
 insert into demo_preserved values(t,pg_temp.config_digest(t));end loop;
 insert into demo_preserved select 'auth.users',md5(string_agg(to_jsonb(x)::text,E'\n' order by id)) from auth.users x;
end$$;

-- Break only the nullable WIP input dependency; these old entries are then deleted.
update public.production_entries set input_lot_id=null where factory_id=pg_temp.f() and input_lot_id is not null;
-- Remove old transfer assignments before closing old execution through its command.
delete from public.production_transfers where factory_id=pg_temp.f();
do $$declare item uuid;begin for item in select id from public.production_orders where factory_id=pg_temp.f() and status='active' loop
 perform public.finish_product_item(pg_temp.f(),item);end loop;end$$;
__DELETES__
-- Transient operating states are reset through the existing commands; permanent configuration stays intact.
do $$declare x record;begin
 for x in select id from public.production_lines where factory_id=pg_temp.f() and paused_at is not null loop
 perform public.set_line_pause(pg_temp.f(),x.id,false,'DEMO reset: clear old operational pause');end loop;
 for x in select id from public.work_centers where factory_id=pg_temp.f() and line_id in
 ('a0c244e3-9d87-52d9-8b12-1a278f6e86d6','b932f276-8b3b-5c0f-99ee-ea75062f938f') and not archived and status<>'running' loop
 perform public.change_status(pg_temp.f(),x.id,'running',null,null,'DEMO reset: ready operating state',null,null,null,false);end loop;
end$$;
delete from public.status_events where factory_id=pg_temp.f();
delete from public.lean_runtime_contexts where factory_id=pg_temp.f();
delete from public.audit_logs where factory_id=pg_temp.f();

create function pg_temp.supply(a text,p jsonb) returns uuid language sql as $$select public.supply_command(pg_temp.f(),a,p,gen_random_uuid())$$;
create function pg_temp.purchase_change(u uuid,a text,reason text default '') returns uuid language sql as $$
 select pg_temp.supply('purchase_change',jsonb_build_object('id',u,'revision',(select revision from public.purchase_requisitions where id=u),'action',a,'reason',reason))$$;
create function pg_temp.material_change(u uuid,a text) returns uuid language sql as $$
 select pg_temp.supply('material_change',jsonb_build_object('id',u,'revision',(select revision from public.material_requests where id=u),'action',a))$$;
create function pg_temp.lean(op text,p jsonb) returns uuid language plpgsql as $$declare u uuid;begin
 perform set_config('request.jwt.claim.sub',pg_temp.lean_actor()::text,true);
 u:=(public.lean_command(pg_temp.f(),gen_random_uuid(),op,p)->>'id')::uuid;
 perform set_config('request.jwt.claim.sub',pg_temp.actor()::text,true);return u;end$$;
create function pg_temp.sales(c text,prod uuid,q numeric,due timestamptz) returns uuid language plpgsql as $$declare u uuid;begin
 u:=public.create_sales_order(pg_temp.f(),jsonb_build_object('customer_reference',c,'requested_delivery',due,
 'notes','DEMO manual acceptance fixture','lines',jsonb_build_array(jsonb_build_object('product_id',prod,'quantity',q,'unit','meter'))),gen_random_uuid());
 perform public.approve_sales_order(pg_temp.f(),u,gen_random_uuid());perform pg_temp.put(c,u);return u;end$$;
create function pg_temp.internal(c text,prod uuid,q numeric,u text default 'meter') returns uuid language plpgsql as $$declare r uuid;i uuid;begin
 r:=public.create_production_request(pg_temp.f(),c,'normal',null,'DEMO manual acceptance batch',
 jsonb_build_array(jsonb_build_object('product_id',prod,'quantity',q,'unit',u)));
 select id into i from public.production_orders where request_id=r;perform pg_temp.put(c,i);return i;end$$;

-- Fresh master identities. Pipes share the authoritative versioned per-kg compound.
do $$declare r uuid;ca uuid;mb uuid;compound uuid;p uuid;x record;begin
 for x in select * from (values
 ('RM-HDPE','HDPE Resin','kg','RAW_MATERIAL',2000::numeric,200::numeric,4000::numeric),
 ('RM-CACO3','Calcium Carbonate','kg','RAW_MATERIAL',100,70,250),
 ('RM-BLACK','Black Masterbatch','kg','RAW_MATERIAL',50,50,100),
 ('AC-BEAR','Extruder bearing','piece','ACCESSORY',0,3,10),
 ('PK-BUNDLE','Pipe bundle straps','piece','PACKAGING',200,50,300))v(code,name,unit,kind,stock,minimum,maximum) loop
 p:=public.create_warehouse_material(pg_temp.f(),jsonb_build_object('code',x.code,'name',x.name,'unit',x.unit,'inventory_kind',x.kind),gen_random_uuid());
 perform pg_temp.put(x.code,p);perform public.configure_warehouse_material(pg_temp.f(),p,x.minimum,x.maximum);
 if x.stock>0 then
 perform public.receive_warehouse_stock(pg_temp.f(),p,'material',x.unit,x.stock,'opening_balance','DEMO-W4','Fixture opening balance');
 update public.inventory_transactions set created_at=(pg_temp.day()-30)::timestamptz where material_id=p;
 end if;
 end loop;
 r:=pg_temp.id('RM-HDPE');ca:=pg_temp.id('RM-CACO3');mb:=pg_temp.id('RM-BLACK');
 compound:=public.define_manufactured_product(pg_temp.f(),null,
 '{"name":"HDPE 80/18/2 compound","code":"C-HDPE","unit":"kg","stock_unit":"kg","product_kind":"MANUFACTURED_INTERMEDIATE","unit_weight_kg":1}',
 jsonb_build_array(jsonb_build_object('material_id',r,'quantity',0.80,'unit','kg'),jsonb_build_object('material_id',ca,'quantity',0.18,'unit','kg'),jsonb_build_object('material_id',mb,'quantity',0.02,'unit','kg')),gen_random_uuid());
 perform pg_temp.put('C-HDPE',compound);
 for x in select * from(values ('P-032','HDPE Pipe 32 mm',0.30::numeric),('P-050','HDPE Pipe 50 mm',0.60),('P-063','HDPE Pipe 63 mm',0.95),('P-BOTH','HDPE Pipe 50 mm - sourced stock',0.60))v(code,name,weight) loop
 p:=public.define_manufactured_product(pg_temp.f(),null,jsonb_build_object('name',x.name,'code',x.code,'unit','meter','stock_unit','meter','unit_weight_kg',x.weight,'formula_product_id',compound),null,gen_random_uuid());
 perform pg_temp.put(x.code,p);
 perform public.configure_warehouse_product(pg_temp.f(),p,case when x.code='P-BOTH' then 'BOTH' else 'MANUFACTURED' end,'MAKE_TO_ORDER','meter',case when x.code='P-050' then 50 else 100 end,case when x.code='P-050' then 600 else 1000 end);
 end loop;
 p:=public.define_manufactured_product(pg_temp.f(),null,'{"name":"Purchased HDPE elbow","code":"P-EXT","unit":"piece","stock_unit":"piece"}',null,gen_random_uuid());
 perform pg_temp.put('P-EXT',p);perform public.configure_warehouse_product(pg_temp.f(),p,'EXTERNAL','MAKE_TO_ORDER','piece',10,50);
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit,setup_minutes)
 select pg_temp.f(),c.id,pg_temp.id(v.code),v.rate,'meter',0 from public.work_centers c join
 (values ('a0c244e3-9d87-52d9-8b12-1a278f6e86d6'::uuid,'P-032',200::numeric),('a0c244e3-9d87-52d9-8b12-1a278f6e86d6','P-050',140),('a0c244e3-9d87-52d9-8b12-1a278f6e86d6','P-BOTH',140),
 ('b932f276-8b3b-5c0f-99ee-ea75062f938f','P-032',160),('b932f276-8b3b-5c0f-99ee-ea75062f938f','P-050',120),('b932f276-8b3b-5c0f-99ee-ea75062f938f','P-063',90),('b932f276-8b3b-5c0f-99ee-ea75062f938f','P-BOTH',120))v(line,code,rate)
 on v.line=c.line_id where c.factory_id=pg_temp.f() and c.code in ('M-02','M-08');
 insert into public.work_center_capabilities values(pg_temp.f(),'d67df71c-f86c-4300-b81b-beb0e47cf67b',pg_temp.id('P-032'),200,'meter',0);
 insert into public.work_center_capabilities values(pg_temp.f(),'c525e1e8-d077-55d2-a7c8-37fa79a37b25',pg_temp.id('P-050'),120,'meter',0);
 insert into public.work_center_capabilities values(pg_temp.f(),'b1812216-ab15-555d-b19e-24b3a71e57bb',compound,50,'kg',0);
 insert into public.production_loss_profiles(factory_id,work_center_id,product_id,can_defer,scrap_expected,updated_by)
 select factory_id,work_center_id,product_id,false,false,pg_temp.actor() from public.work_center_capabilities where factory_id=pg_temp.f();
 for x in select distinct c.line_id,k.product_id from public.work_center_capabilities k join public.work_centers c on c.id=k.work_center_id where k.factory_id=pg_temp.f() and c.line_id is not null loop
 perform pg_temp.lean('standard',jsonb_build_object('id',gen_random_uuid(),'line_id',x.line_id,'product_id',x.product_id,'running_percent',2,'startup_kg',1,'expected_revision',0));end loop;
 perform pg_temp.assert_demo((select sum(quantity)=1 from public.bom_items where factory_id=pg_temp.f()),'recipe kg sums to one');
end$$;

-- Historical fixture timelines are source events, not manually supplied metrics.
create temp table demo_history(item uuid primary key,sales uuid,line uuid,product uuid,started timestamptz,finished timestamptz,ordinal integer,entry uuid) on commit drop;
create temp table demo_stops(event uuid primary key,item uuid,started timestamptz,ended timestamptz,borrowed boolean default false) on commit drop;
create function pg_temp.history_stop(i uuid,w uuid,at_time timestamptz,minutes integer,cause_name text,label text,borrowed boolean default false,pending boolean default false) returns uuid language plpgsql as $$
 declare d uuid;cause uuid;line uuid;begin
 select line_id into line from public.production_orders where id=i;
 select id into cause from public.downtime_reasons where factory_id=pg_temp.f() and name=cause_name;
 insert into public.downtime_events(factory_id,work_center_id,reason_id,started_at,ended_at,notes,initial_note,created_by,entered_by,
 stop_nature,loss_model_version,initial_entered_by,initial_entered_at)
 values(pg_temp.f(),w,(select id from public.downtime_reasons where factory_id=pg_temp.f() and name='Other'),at_time,at_time+make_interval(mins=>minutes),
 label||' - DEMO historical source fixture',label||': operator reported vibration / unstable output',pg_temp.actor(),pg_temp.actor(),'unplanned',1,pg_temp.actor(),at_time) returning id into d;
 if not pending then
 perform public.approve_downtime_cause(pg_temp.f(),d,cause,'DEMO engineer reviewed fixture cause');
 end if;
 perform public.record_production_loss_actuals(pg_temp.f(),d,0,'kg',null,null,null,null,null,null);
 insert into demo_stops values(d,i,at_time,at_time+make_interval(mins=>minutes),borrowed);
 if borrowed then
 insert into public.production_transfers(factory_id,original_id,alternative_id,order_id,downtime_id,reason,created_at,created_by,ended_at,original_returned_at)
 values(pg_temp.f(),w,'301cf73f-2cdf-5bf9-ab4d-1154fec16340',i,d,'DEMO-D2 historical alternative cover',at_time,pg_temp.actor(),at_time+make_interval(mins=>minutes),at_time+make_interval(mins=>minutes));end if;
 return d;end$$;
create function pg_temp.record_fixture(i uuid,line uuid,good numeric,scrap numeric,wip numeric,at_time timestamptz,lot uuid default null,input numeric default 0,discarded numeric default 0) returns uuid language plpgsql as $$
 declare e uuid;shift uuid;tech uuid;begin
 select id into tech from public.memberships where factory_id=pg_temp.f() and user_id=pg_temp.actor();
 shift:=private.resolve_factory_shift(pg_temp.f(),at_time);
 e:=(public.record_lean_production(pg_temp.f(),jsonb_build_object('unit_kind','line','production_unit',line,'item',i,'technician',tech,'good',good,
 'discarded_quantity',discarded,'scrap_kg',scrap,'startup_kg',0,'unfinished',wip,'remaining_work',case when wip>0 then 'Printing and inspection' else '' end,
 'input_lot',lot,'input_quantity',input,'shift',shift,'shift_override_reason','DEMO historical fixture shift attribution','notes','DEMO historical declaration'),gen_random_uuid())->>'id')::uuid;
 update public.production_entries set created_at=at_time,shift_override_at=at_time where id=e;
 update public.finished_goods_movements set created_at=at_time where entry_id=e;
 update public.unfinished_lots set created_at=at_time where source_entry_id=e;
 update public.unfinished_operations set created_at=at_time where entry_id=e;
 update public.unfinished_movements set created_at=at_time where entry_id=e;
 return e;end$$;
create function pg_temp.scrap_review(e uuid,at_time timestamptz,cause_name text,linked uuid default null,pending boolean default false) returns uuid language plpgsql as $$declare u uuid;cause uuid;begin
 select id into cause from public.downtime_reasons where factory_id=pg_temp.f() and name=cause_name;
 u:=pg_temp.lean('scrap_observation',jsonb_build_object('id',gen_random_uuid(),'entry_id',e,'occurred_at',at_time,
 'preliminary_cause_id',(select id from public.downtime_reasons where factory_id=pg_temp.f() and name='Other'),
 'observation','DEMO operator observed surface defect','response','Segregated scrap and checked process','downtime_id',linked));
 if not pending then
 perform pg_temp.lean('scrap_review',jsonb_build_object('id',u,'approved_cause_id',cause,'note','DEMO engineer confirmed physical source','expected_revision',1));
 update public.lean_scrap_events set reviewed_at=at_time+interval '5 minutes' where id=u;
 end if;
 return u;end$$;

do $$declare line1 uuid:='a0c244e3-9d87-52d9-8b12-1a278f6e86d6';line2 uuid:='b932f276-8b3b-5c0f-99ee-ea75062f938f';
 sales uuid;i uuid;line uuid;prod uuid;start_at timestamptz;finish_at timestamptz;actual_end timestamptz;e uuid;e2 uuid;lot uuid;d uuid;q numeric;rate numeric;n integer;k integer;offset_days integer;code text;scrap numeric;begin
 -- One stock-only historical order, followed by one partial-stock historical order.
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('P-050'),'finished','meter',100,'opening_balance','DEMO-H0');
 update public.finished_goods_movements set created_at=(pg_temp.day()-30)::timestamptz where product_id=pg_temp.id('P-050') and kind='opening_balance';
 sales:=pg_temp.sales('DEMO-H0 stock-only',pg_temp.id('P-050'),100,(pg_temp.day()-29)::timestamptz);
 perform public.dispatch_sales_order(pg_temp.f(),sales,null,gen_random_uuid());
 update public.sales_orders set created_at=(pg_temp.day()-30)::timestamptz,approved_at=(pg_temp.day()-29)::timestamptz where id=sales;
 update public.finished_goods_movements set created_at=(pg_temp.day()-29)::timestamptz where sales_line_id in(select id from public.sales_order_lines where order_id=sales);
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('P-032'),'finished','meter',100,'opening_balance','DEMO-H1 partial-stock');
 update public.finished_goods_movements set created_at=(pg_temp.day()-29)::timestamptz where product_id=pg_temp.id('P-032') and kind='opening_balance';
 n:=0;
 foreach offset_days in array array[28,24,20,16,12,8,4,1] loop
 n:=n+1;
 for k in 1..2 loop
 line:=case when k=1 then line1 else line2 end;
 prod:=pg_temp.id(case when k=1 then 'P-032' when n in (3,8) then 'P-063' else 'P-050' end);
 q:=case when k=1 then 600 when n in (3,8) then 270 else 360 end;
 rate:=case when k=1 then 200 when n in (3,8) then 90 else 120 end;
 start_at:=private.next_working_start(pg_temp.f(),(pg_temp.day()-offset_days+case when k=1 then time '09:00' else time '14:00' end) at time zone 'Asia/Qatar');
 finish_at:=private.finish_after_working_minutes(pg_temp.f(),start_at,180);
 code:=format('DEMO-H%s-L%s',lpad(n::text,2,'0'),k);
 sales:=pg_temp.sales(code,prod,q+case when n=1 and k=1 then 100 else 0 end,finish_at+interval '1 day');
 select o.id into i from public.production_orders o join public.production_requests r on r.id=o.request_id join public.sales_order_lines sl on sl.id=r.sales_order_line_id where sl.order_id=sales;
 perform pg_temp.assert_demo(i is not null,'historical Sales created exact shortage '||code);
 update public.production_orders set line_id=line,start_time=start_at,expected_finish=finish_at where id=i;
 update public.production_orders set status='active',actual_start=start_at+interval '5 minutes' where id=i;
 actual_end:=finish_at+case when n=3 then interval '20 minutes' else interval '5 minutes' end;
 -- Early bearing-loss baseline, smaller later loss, and post-verification recurrence.
 if k=1 and n<>3 then
 d:=pg_temp.history_stop(i,'e106358c-0022-5661-b3ce-9cc626e7e3c2',start_at+interval '20 minutes',case when n<=2 then 30 when n<=5 then 5 else 10 end,'Bearing failure','DEMO-D1 loss time');
 end if;
 if k=1 and n>=6 then
 perform pg_temp.history_stop(i,'e106358c-0022-5661-b3ce-9cc626e7e3c2',start_at+interval '70 minutes',2,'Die blockage','DEMO-D3 short recurrence');
 perform pg_temp.history_stop(i,'e106358c-0022-5661-b3ce-9cc626e7e3c2',start_at+interval '100 minutes',2,'Die blockage','DEMO-D3 short recurrence');end if;
 if k=1 and n=3 then d:=pg_temp.history_stop(i,'e106358c-0022-5661-b3ce-9cc626e7e3c2',start_at+interval '65 minutes',20,'Mechanical problem','DEMO-D2 alternative mitigation',true);end if;
 if k=2 and n not in (3,8) then d:=pg_temp.history_stop(i,'301cf73f-2cdf-5bf9-ab4d-1154fec16340',start_at+case when n=2 then interval '90 minutes' else interval '20 minutes' end,30,'Cooling water flow / pressure problem','DEMO-D4 unchanged loss');end if;
 scrap:=case when k=1 and n in (1,2) then 8 when k=1 and n in (4,5,6,7) then 25 when k=2 and n not in (3,8) then 12 when k=2 and n in (3,8) then 20 else 0 end;
 if k=1 and n=3 then
 e:=pg_temp.record_fixture(i,line,540,3,100,start_at+interval '2 hours');
 select id into lot from public.unfinished_lots where source_entry_id=e;
 e2:=pg_temp.record_fixture(i,line,60,5,35,start_at+interval '2 hours 55 minutes',lot,100,5);
 perform pg_temp.scrap_review(e2,start_at+interval '2 hours 55 minutes','Material recipe / mixture problem');
 select id into lot from public.unfinished_lots where source_entry_id=e2;
 perform pg_temp.supply('receive_wip',jsonb_build_object('lot',lot,'quantity',20));
 perform pg_temp.assert_demo((select input_quantity=effective_good+effective_scrap+effective_unfinished and effective_scrap=5 and effective_scrap_kg=5 from public.production_entries where id=e2),'WIP input100 = Good60 + discarded5 + WIP35');
 else
 e:=pg_temp.record_fixture(i,line,q*2/3,scrap,0,start_at+interval '2 hours');
 e2:=pg_temp.record_fixture(i,line,q/3,case when k=2 and n=3 then 3 when k=2 and n=4 then 10 else 0 end,0,start_at+interval '2 hours 55 minutes');end if;
 if scrap>0 then perform pg_temp.scrap_review(e,start_at+interval '2 hours',case when k=1 then 'Material recipe / mixture problem' else 'Raw-material quality problem' end,null,k=2 and n=8);end if;
 if k=2 and n=3 then perform pg_temp.scrap_review(e2,start_at+interval '2 hours 55 minutes','Raw-material quality problem');end if;
 -- One explicit physical stop/quality link, counted once by authoritative occurrences.
 if k=2 and n=4 then
 d:=pg_temp.history_stop(i,'c525e1e8-d077-55d2-a7c8-37fa79a37b25',start_at+interval '110 minutes',15,'Printing defect','DEMO-L4 multiple dimensions');
 perform pg_temp.scrap_review(e2,start_at+interval '115 minutes','Printing defect',d);end if;
 update public.production_orders set status='completed',actual_finish=actual_end where id=i;
 perform public.dispatch_sales_order(pg_temp.f(),sales,null,gen_random_uuid());
 update public.sales_orders set created_at=start_at-interval '2 days',approved_at=start_at-interval '1 day' where id=sales;
 update public.finished_goods_movements set created_at=case when kind='reservation' then
 case when n=1 and k=1 and reserved_delta=100 then start_at-interval '1 day' else start_at+interval '2 hours 55 minutes' end
 else actual_end end where sales_line_id in(select id from public.sales_order_lines where order_id=sales);
 update public.production_plan_revisions set changed_at=start_at-interval '1 day' where item_id=i;
 if n=3 and k=1 then
 update public.production_plan_revisions set after_line_id=line2,after_start=start_at-interval '30 minutes',after_finish=start_at+interval '3 hours 15 minutes' where item_id=i and revision_no=1;
 insert into public.production_plan_revisions(factory_id,item_id,revision_no,event,before_line_id,before_start,before_finish,after_line_id,after_start,after_finish,reason_code,reason_note,changed_by,changed_by_name,changed_at)
 values(pg_temp.f(),i,2,'replanned',line2,start_at-interval '30 minutes',start_at+interval '3 hours 15 minutes',line1,start_at,finish_at,'material_delay','DEMO historical fixture: compound delivery moved the batch to LINE 1',pg_temp.actor(),'Nasser Al Kuwari',start_at-interval '12 hours');
 end if;
 if n=1 and k=1 then
 perform pg_temp.supply('acknowledge_good',jsonb_build_object('entry',e2));
 update public.production_receipt_acknowledgments set received_at=start_at+interval '3 hours' where entry_id=e2;
 perform pg_temp.assert_demo((select received_good=q/3 from public.finished_goods_entry_receipts where entry_id=e2),'Good acknowledgment leaves credited Good unchanged');end if;
 insert into demo_history values(i,sales,line,prod,start_at+interval '5 minutes',actual_end,n,e);
 perform pg_temp.put(code||'-ITEM',i);
 end loop;end loop;
end$$;

-- Import the fully specified historical physical contexts, tagged as fixtures.
-- No real telemetry/capture claim. Metrics are subsequently computed by evaluateFlow.
create function pg_temp.fixture_context(at_time timestamptz) returns jsonb language sql as $$
 select jsonb_build_object('demo_fixture',true,'timezone','Asia/Qatar',
 'centers',(select jsonb_agg(to_jsonb(c)||jsonb_build_object('status',case when exists(select 1 from demo_stops s join public.downtime_events d on d.id=s.event where d.work_center_id=c.id and s.started<=at_time and s.ended>at_time) then 'stopped' else 'running' end,
 'order_id',(select h.item from demo_history h where h.line=c.line_id and h.started<=at_time and h.finished>at_time))) from public.work_centers c where factory_id=pg_temp.f()),
 'stops',(select coalesce(jsonb_agg(to_jsonb(d)||jsonb_build_object('ended_at',null)),'[]') from demo_stops s join public.downtime_events d on d.id=s.event where s.started<=at_time and s.ended>at_time),
 'transfers',(select coalesce(jsonb_agg(to_jsonb(t)||jsonb_build_object('ended_at',null)),'[]') from public.production_transfers t where factory_id=pg_temp.f() and created_at<=at_time and ended_at>at_time),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o)||jsonb_build_object('status','active','actual_finish',null)),'[]') from demo_history h join public.production_orders o on o.id=h.item where h.started<=at_time and h.finished>at_time),
 'products',(select jsonb_agg(to_jsonb(p)) from public.products p where factory_id=pg_temp.f()),
 'capabilities',(select jsonb_agg(to_jsonb(p)) from public.work_center_capabilities p where factory_id=pg_temp.f()),
 'profiles',(select jsonb_agg(to_jsonb(p)) from public.production_loss_profiles p where factory_id=pg_temp.f()),
 'recovery_rates','[]'::jsonb,'alternatives',(select jsonb_agg(to_jsonb(p)) from public.work_center_alternatives p where factory_id=pg_temp.f()),
 'lines',(select jsonb_agg(to_jsonb(l)||jsonb_build_object('paused_at',null)) from public.production_lines l where factory_id=pg_temp.f()),
 'shifts',(select jsonb_agg(to_jsonb(p)) from public.production_shifts p where factory_id=pg_temp.f()))$$;
delete from public.production_loss_context_snapshots where factory_id=pg_temp.f();
insert into public.production_loss_context_snapshots(factory_id,event_id,captured_at,context)
 select pg_temp.f(),s.event,p.at_time,pg_temp.fixture_context(p.at_time) from demo_stops s cross join lateral
 (select s.started at_time union select d.started from demo_stops d where d.started>s.started and d.started<s.ended union select d.ended from demo_stops d where d.ended>s.started and d.ended<s.ended)p;
delete from public.lean_runtime_contexts where factory_id=pg_temp.f();
insert into public.lean_runtime_contexts(factory_id,captured_at,context)
 select pg_temp.f(),at_time,pg_temp.fixture_context(at_time) from
 (select (pg_temp.day()-30)::timestamptz at_time union select min(started)-interval '1 second' from demo_history union select started from demo_history union select finished from demo_history union select started from demo_stops union select ended from demo_stops)points order by at_time;

-- Explicit historical material requests: theoretical recipe never consumes stock itself.
do $$declare x record;r uuid;begin
 for x in select * from(values('RM-HDPE',144::numeric),('RM-CACO3',32.4),('RM-BLACK',3.6))v(code,q) loop
 r:=pg_temp.supply('material_request',jsonb_build_object('item',pg_temp.id(x.code),'quantity',x.q,'unit','kg','note','DEMO-W3: materials for 180kg compound / 600m P-032'));
 perform pg_temp.material_change(r,'issue');perform pg_temp.material_change(r,'receive');
 update public.material_requests set created_at=(pg_temp.day()-28)::timestamptz,issued_at=(pg_temp.day()-28)::timestamptz+interval '6 hours',received_at=(pg_temp.day()-28)::timestamptz+interval '6 hours 10 minutes' where id=r;
 update public.inventory_transactions set created_at=(pg_temp.day()-28)::timestamptz+interval '6 hours' where id=(select movement_id from public.material_requests where id=r);
 end loop;
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('P-032'),'finished','meter',400,'external_receipt','DEMO current carry-over stock');
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('P-050'),'finished','meter',1200,'external_receipt','DEMO current carry-over stock');
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('C-HDPE'),'finished','kg',100,'opening_balance','DEMO compound stock');
end$$;

-- Current department scenarios. Leave S2/S3 unscheduled.
do $$declare sales uuid;i uuid;r uuid;supplier uuid;alt uuid;x record;pending uuid;line1 uuid:='a0c244e3-9d87-52d9-8b12-1a278f6e86d6';line2 uuid:='b932f276-8b3b-5c0f-99ee-ea75062f938f';begin
 perform pg_temp.sales('DEMO-S1 fully available',pg_temp.id('P-050'),300,(pg_temp.day()+5)::timestamptz);
 perform pg_temp.sales('DEMO-S2 partial stock',pg_temp.id('P-032'),1000,(pg_temp.day()+8)::timestamptz);
 perform pg_temp.sales('DEMO-S3 full shortage',pg_temp.id('P-063'),200,(pg_temp.day()+10)::timestamptz);
 sales:=pg_temp.sales('DEMO-S4 tight date',pg_temp.id('P-050'),1000,(pg_temp.day()+1)::timestamptz);
 select o.id into i from public.production_orders o join public.production_requests r on r.id=o.request_id join public.sales_order_lines l on l.id=r.sales_order_line_id where l.order_id=sales;
 perform public.plan_product_item(pg_temp.f(),i,line1,(pg_temp.day()+4+time '09:00') at time zone 'Asia/Qatar');
 sales:=pg_temp.sales('DEMO-S5 comfortable date',pg_temp.id('P-050'),300,(pg_temp.day()+10)::timestamptz);
 select o.id into i from public.production_orders o join public.production_requests r on r.id=o.request_id join public.sales_order_lines l on l.id=r.sales_order_line_id where l.order_id=sales;
 perform public.plan_product_item(pg_temp.f(),i,line2,(pg_temp.day()+2+time '13:00') at time zone 'Asia/Qatar');
 i:=pg_temp.internal('DEMO-PR3 active production',pg_temp.id('P-050'),560);
 perform public.plan_product_item(pg_temp.f(),i,line1,clock_timestamp()+interval '2 minutes');
 perform public.start_product_item(pg_temp.f(),i);
 r:=pg_temp.supply('material_request',jsonb_build_object('item',pg_temp.id('RM-HDPE'),'quantity',20,'unit','kg','note','DEMO-W1 pending warehouse issue','production_item_id',i));perform pg_temp.put('DEMO-W1',r);
 r:=pg_temp.supply('material_request',jsonb_build_object('item',pg_temp.id('RM-CACO3'),'quantity',5,'unit','kg','note','DEMO-W2 issued, original requester receipt pending','production_item_id',i));
 perform pg_temp.material_change(r,'issue');perform pg_temp.put('DEMO-W2',r);
 i:=pg_temp.internal('DEMO-P2 ready to start',pg_temp.id('P-050'),280);
 perform public.plan_product_item(pg_temp.f(),i,line1,(pg_temp.day()+1+time '09:00') at time zone 'Asia/Qatar');
 i:=pg_temp.internal('DEMO-P3 locked future job',pg_temp.id('P-032'),400);
 perform public.plan_product_item(pg_temp.f(),i,line2,(pg_temp.day()+2+time '09:00') at time zone 'Asia/Qatar');perform public.set_plan_lock(pg_temp.f(),i,true);
 i:=pg_temp.internal('DEMO-P4 reasoned replan',pg_temp.id('P-050'),120);
 perform public.plan_product_item(pg_temp.f(),i,line1,(pg_temp.day()+6+time '09:00') at time zone 'Asia/Qatar');
 perform public.revise_product_plan(pg_temp.f(),i,line2,(pg_temp.day()+7+time '09:00') at time zone 'Asia/Qatar','material_delay','DEMO resin delivery shifted this job');
 perform pg_temp.internal('DEMO-PR1 manager assignment / compound batch',pg_temp.id('C-HDPE'),50,'kg');
 -- Current open transfer uses real commands. Borrower's permanent line remains unchanged.
 perform public.change_status(pg_temp.f(),'e106358c-0022-5661-b3ce-9cc626e7e3c2','stopped',(select id from public.downtime_reasons where factory_id=pg_temp.f() and name='Other'),null,'DEMO-D2 current test: alternative maintains flow',null,null,null,false);
 perform public.change_status(pg_temp.f(),'301cf73f-2cdf-5bf9-ab4d-1154fec16340','idle',null,null,'DEMO alternative available for borrowing',null,null,null,false);
 perform public.transfer_production(pg_temp.f(),'e106358c-0022-5661-b3ce-9cc626e7e3c2','301cf73f-2cdf-5bf9-ab4d-1154fec16340','DEMO current alternative cover');
 -- Compact supplier directory, with normalized Primary / Alternative references.
 supplier:=pg_temp.supply('supplier_save','{"name":"Gulf Polymer Supply","primary_contact":"Demo sales desk","email":"polymer@example.test","category":"HDPE ingredients","relationship":"PRIMARY"}');
 alt:=pg_temp.supply('supplier_save','{"name":"Doha Industrial Materials","email":"materials@example.test","category":"HDPE ingredients","relationship":"ALTERNATIVE"}');
 perform pg_temp.put('SUPPLIER-PRIMARY',supplier);perform pg_temp.put('SUPPLIER-ALTERNATIVE',alt);
 -- Every purchase state is reached through the protected workflow.
 for x in select * from(values
 ('DEMO-B1 requested','REQUESTED','RM-BLACK',10::numeric),('DEMO-B2 review','UNDER_REVIEW',null,1),
 ('DEMO-B3 clarification','NEEDS_CLARIFICATION',null,1),('DEMO-B4 ordered','ORDERED','AC-BEAR',3),
 ('DEMO-B5 ready stock','READY_FOR_RECEIPT','RM-CACO3',100),('DEMO-B6 received stock','RECEIVED','RM-HDPE',200),
 ('DEMO-B7 received direct','RECEIVED',null,1),('DEMO-B8 rejected','REJECTED',null,1),('DEMO-B9 cancelled','CANCELLED',null,1),
 ('DEMO-B10 ready direct','READY_FOR_RECEIPT',null,2),('DEMO-B11 own cancellation','REQUESTED',null,1))v(code,state,material,q) loop
 if x.material is null then r:=pg_temp.supply('purchase_manual',jsonb_build_object('item_name',x.code,'quantity',x.q,'unit','piece','details',x.code||' - pressure gauge / calibration service specification','source_context','Production'));
 else r:=pg_temp.supply('purchase_inventory',jsonb_build_object('item',pg_temp.id(x.material),'quantity',x.q,'unit',case when x.material='AC-BEAR' then 'piece' else 'kg' end,'details',x.code));end if;
 perform pg_temp.put(x.code,r);
 if x.state not in ('REQUESTED','NEEDS_CLARIFICATION','REJECTED','CANCELLED') then
 perform pg_temp.supply('purchase_change',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r),'action','supplier',case when x.code like 'DEMO-B10%' then 'supplier_text' else 'supplier_id' end,case when x.code like 'DEMO-B10%' then 'Demo on-site calibration workshop' else supplier::text end));
 perform pg_temp.purchase_change(r,'UNDER_REVIEW');
 if x.state<>'UNDER_REVIEW' then perform pg_temp.purchase_change(r,'ORDERED');end if;
 if x.state in ('READY_FOR_RECEIPT','RECEIVED') then perform pg_temp.purchase_change(r,'READY_FOR_RECEIPT');end if;
 if x.state='RECEIVED' then
 if x.material is null then perform pg_temp.purchase_change(r,'receive_direct');else perform pg_temp.supply('receive_purchase',jsonb_build_object('id',r,'revision',(select revision from public.purchase_requisitions where id=r)));end if;
 update public.purchase_requisitions set created_at=(pg_temp.day()-16)::timestamptz,received_at=(pg_temp.day()-12)::timestamptz where id=r;
 update public.purchase_request_events set created_at=(pg_temp.day()-16)::timestamptz+case status
 when 'REQUESTED' then interval '0 days' when 'UNDER_REVIEW' then interval '1 day' when 'ORDERED' then interval '2 days'
 when 'READY_FOR_RECEIPT' then interval '3 days' else interval '4 days' end where request_id=r;
 update public.inventory_transactions set created_at=(pg_temp.day()-12)::timestamptz where id=(select receipt_movement_id from public.purchase_requisitions where id=r);end if;
 elsif x.state in ('NEEDS_CLARIFICATION','REJECTED','CANCELLED') then perform pg_temp.purchase_change(r,x.state,'DEMO: confirm gauge size / duplicate requirement');end if;
 end loop;
 perform public.receive_warehouse_stock(pg_temp.f(),pg_temp.id('P-EXT'),'finished','piece',2,'external_receipt','DEMO-W5');
end$$;

-- Maintenance: manual requests remain independent of machine state; separate person verifies.
do $$declare x record;r uuid;d uuid;worker uuid:='90a63464-4abd-5143-b2c2-062fd16efb53';before_state text;begin
 select status into before_state from public.work_centers where code='M-01' and factory_id=pg_temp.f();
 for x in select * from(values('DEMO-M1 manual open','OPEN'),('DEMO-M2 assigned','ASSIGNED'),('DEMO-M3 work in progress','IN_PROGRESS'),
 ('DEMO-M4 awaiting verification','COMPLETED'),('DEMO-M5 historical verified','VERIFIED'),('DEMO-M6 historical cancelled','CANCELLED'),('DEMO-M7 failed verification','REWORK'))v(title,state) loop
 select event into d from demo_stops order by started limit 1;
 r:=public.create_maintenance_request(pg_temp.f(),jsonb_build_object('work_center_id',case when x.state='VERIFIED' then 'e106358c-0022-5661-b3ce-9cc626e7e3c2' else 'b1812216-ab15-555d-b19e-24b3a71e57bb' end,
 'downtime_id',case when x.state='VERIFIED' then d end,'title',x.title,'description','DEMO bearing noise / inspection request','priority','NORMAL','separate_problem',true),gen_random_uuid());
 perform pg_temp.put(x.title,r);
 if x.state not in ('OPEN','CANCELLED') then
 perform public.change_maintenance_request(pg_temp.f(),r,'assign',jsonb_build_object('assigned_to',worker),(select revision from public.maintenance_requests where id=r),gen_random_uuid());
 if x.state<>'ASSIGNED' then
 perform set_config('request.jwt.claim.sub',worker::text,true);perform public.change_maintenance_request(pg_temp.f(),r,'start','{}',(select revision from public.maintenance_requests where id=r),gen_random_uuid());
 if x.state<>'IN_PROGRESS' then perform public.change_maintenance_request(pg_temp.f(),r,'complete','{"work_note":"DEMO inspected and aligned bearing coupling"}',(select revision from public.maintenance_requests where id=r),gen_random_uuid());end if;
 perform set_config('request.jwt.claim.sub',pg_temp.actor()::text,true);
 if x.state in ('VERIFIED','REWORK') then perform public.change_maintenance_request(pg_temp.f(),r,'verify',jsonb_build_object('result',case when x.state='VERIFIED' then 'RESOLVED' else 'REWORK_REQUIRED' end,'verification_note','DEMO independent production trial review'),(select revision from public.maintenance_requests where id=r),gen_random_uuid());end if;
 end if;
 elsif x.state='CANCELLED' then perform public.change_maintenance_request(pg_temp.f(),r,'cancel','{"cancellation_note":"DEMO duplicate inspection withdrawn"}',1,gen_random_uuid());end if;
 if x.state in ('VERIFIED','CANCELLED','COMPLETED','REWORK') then update public.maintenance_requests set created_at=(pg_temp.day()-20)::timestamptz,requested_at=(pg_temp.day()-20)::timestamptz,
 assigned_at=case when assigned_at is not null then (pg_temp.day()-19)::timestamptz end,started_at=case when started_at is not null then (pg_temp.day()-19)::timestamptz+interval '1 hour' end,
 completed_at=case when completed_at is not null then (pg_temp.day()-18)::timestamptz end,verified_at=case when verified_at is not null then (pg_temp.day()-17)::timestamptz end,
 cancelled_at=case when cancelled_at is not null then (pg_temp.day()-19)::timestamptz end,checked_at=case when checked_at is not null then (pg_temp.day()-17)::timestamptz end where id=r;end if;
 end loop;
 perform pg_temp.assert_demo((select status=before_state from public.work_centers where code='M-01' and factory_id=pg_temp.f()),'MANUAL maintenance does not change machine state');
 select event into d from demo_stops order by started limit 1;
 r:=public.create_maintenance_request(pg_temp.f(),jsonb_build_object('work_center_id','e106358c-0022-5661-b3ce-9cc626e7e3c2','downtime_id',d,'title','DEMO-M8 downtime-linked open','priority','HIGH'),gen_random_uuid());
 perform pg_temp.put('DEMO-M8',r);
end$$;

-- Frozen historical improvement windows are tied to actual imported source boundaries.
do $$declare x record;p uuid;i uuid;a uuid;b uuid;cause uuid;from_at timestamptz;to_at timestamptz;prod uuid;line uuid;machine uuid;begin
 for x in select * from(values
 ('DEMO-I5 improved','downtime','Bearing failure','P-032','M-02'),
 ('DEMO-I6 no meaningful change','downtime','Cooling water flow / pressure problem','P-050','M-08'),
 ('DEMO-I7 worse','scrap','Material recipe / mixture problem','P-032',null),
 ('DEMO-I8 insufficient data','scrap','Raw-material quality problem','P-063',null),
 ('DEMO-I2 in progress','downtime','Die blockage','P-032','M-02'),
 ('DEMO-I4 awaiting verification','scrap','Raw-material quality problem','P-050',null))v(title,mechanism,cause,product,machine) loop
 select id into cause from public.downtime_reasons where factory_id=pg_temp.f() and name=x.cause;
 prod:=pg_temp.id(x.product);select id,line_id into machine,line from public.work_centers where factory_id=pg_temp.f() and code=x.machine;
 if x.mechanism='scrap' then line:=case when x.product='P-032' then 'a0c244e3-9d87-52d9-8b12-1a278f6e86d6'::uuid else 'b932f276-8b3b-5c0f-99ee-ea75062f938f'::uuid end;machine:=null;else line:=null;end if;
 p:=pg_temp.lean('problem',jsonb_build_object('mechanism',x.mechanism,'machine_id',machine,'line_id',line,'product_id',case when x.mechanism='scrap' then prod end,'cause_id',cause,'expected_revision',0));
 if x.title like 'DEMO-I8%' then
 select min(occurred_at),max(occurred_at) into from_at,to_at from public.lean_scrap_events where factory_id=pg_temp.f() and product_id=prod and reviewed_at is not null;
 else
 if x.mechanism='downtime' then
 select min(d.started_at),max(d.ended_at) into from_at,to_at from public.downtime_events d join demo_history h on h.item=d.order_id
 where h.ordinal in (1,2) and h.product=prod and d.approved_cause_id=cause and d.work_center_id=machine;
 else
 select min(s.occurred_at),max(s.occurred_at) into from_at,to_at from public.lean_scrap_events s join public.production_entries e on e.id=s.entry_id join demo_history h on h.item=e.order_id
 where h.ordinal in (1,2) and h.product=prod and s.approved_cause_id=cause;
 end if;
 end if;
 if x.title like 'DEMO-I2%' then select min(started),max(ended) into from_at,to_at from demo_stops s join public.downtime_events d on d.id=s.event where d.approved_cause_id=cause;end if;
 i:=gen_random_uuid();
 insert into public.lean_initiatives(id,factory_id,problem_id,product_id,title,baseline_from,baseline_to,created_by,created_at)
 values(i,pg_temp.f(),p,prod,x.title,from_at,to_at,pg_temp.lean_actor(),to_at);
 perform pg_temp.put(x.title,i);
 a:=pg_temp.lean('action',jsonb_build_object('id',gen_random_uuid(),'initiative_id',i,'title','DEMO inspect '||x.cause,'description','Check the recorded physical cause; no AI root cause','action_type','MAINTENANCE','owner_id','90a63464-4abd-5143-b2c2-062fd16efb53','due_date',pg_temp.day()+3));
 b:=pg_temp.lean('action',jsonb_build_object('id',gen_random_uuid(),'initiative_id',i,'title','DEMO process setting confirmation','action_type','PROCESS','owner_id',pg_temp.actor(),'due_date',pg_temp.day()+4));
 if x.title like 'DEMO-I2%' then
 perform pg_temp.lean('progress',jsonb_build_object('id',a,'status','IN_PROGRESS','due_date',pg_temp.day()+3,'note','DEMO diagnosis underway','expected_revision',1));
 perform pg_temp.lean('cancel_action',jsonb_build_object('id',b,'reason','DEMO superseded setting change; keep history','expected_revision',1));
 else
 perform pg_temp.lean('progress',jsonb_build_object('id',a,'status','COMPLETED','due_date',pg_temp.day()+3,'note','DEMO historical action completed','expected_revision',1));
 perform pg_temp.lean('progress',jsonb_build_object('id',b,'status','COMPLETED','due_date',pg_temp.day()+4,'note','DEMO historical process check completed','expected_revision',1));
 update public.lean_initiatives set completed_at=(pg_temp.day()-20+time '23:00') at time zone 'Asia/Qatar' where id=i;
 if x.title like 'DEMO-I8%' then update public.lean_initiatives set completed_at=(pg_temp.day()-1+time '23:00') at time zone 'Asia/Qatar' where id=i;end if;
 update public.lean_actions set created_at=to_at+interval '30 minutes',updated_at=(select completed_at from public.lean_initiatives where id=i) where initiative_id=i;
 end if;
 perform pg_temp.lean('template',jsonb_build_object('id',gen_random_uuid(),'cause_id',cause,'title','Inspect '||x.cause,'name_ar','فحص السبب المسجل','description','DEMO reusable suggestion; management chooses the action','action_type','MAINTENANCE','due_days',3));
 end loop;
 -- Monitor-only alternative case with no initiative.
 select id into cause from public.downtime_reasons where factory_id=pg_temp.f() and name='Mechanical problem';
 perform pg_temp.lean('problem',jsonb_build_object('mechanism','downtime','machine_id','e106358c-0022-5661-b3ce-9cc626e7e3c2','cause_id',cause,'monitor_only',true,'expected_revision',0));
end$$;

set constraints all immediate;
do $$declare x record;begin
 for x in select * from demo_preserved where name<>'auth.users' loop perform pg_temp.assert_demo(pg_temp.config_digest(x.name)=x.digest,'preserved '||x.name);end loop;
 perform pg_temp.assert_demo((select md5(string_agg(to_jsonb(au)::text,E'\n' order by id)) from auth.users au)=(select digest from demo_preserved where name='auth.users'),'existing auth users unchanged');
 perform pg_temp.assert_demo((select count(*)=6 from public.products where factory_id=pg_temp.f()),'six fresh Product identities only');
 perform pg_temp.assert_demo((select count(*)=5 from public.materials where factory_id=pg_temp.f()),'five fresh Warehouse materials only');
 perform pg_temp.assert_demo(not exists(select 1 from public.production_orders where factory_id=pg_temp.f() and status='active' group by line_id having count(*)>1),'at most one active Product Item per line');
 perform pg_temp.assert_demo((select quantity_available=35 and warehouse_quantity=20 from public.unfinished_lots where quantity_available>0 and factory_id=pg_temp.f()),'WIP35 total / stored20 / floor15');
end$$;
select jsonb_build_object('day',pg_temp.day(),'checks',(select count(*) from demo_checks),'scenarios',(select jsonb_object_agg(code,id) from demo_ids),'history_from',(select min(started) from demo_history),'history_to',(select max(finished) from demo_history)) as seeded;
__END__
