-- Standalone localhost fixture only. Every write rolls back; no hosted account.
begin;
create function pg_temp.q_assert(ok boolean,label text) returns void language plpgsql as $$begin
 if ok is distinct from true then raise exception 'High Scrap: %',label;end if;raise notice 'PASS %',label;end$$;
create function pg_temp.q_read(f uuid,e uuid) returns jsonb language sql as $$
 select public.quality_read(f,jsonb_build_object('mode','board','entry',e))->'rows'->0->'scrap'
$$;
create function pg_temp.q_error(statement text) returns void language plpgsql as $$begin
 begin execute statement;exception when insufficient_privilege then raise notice 'PASS permission denial';return;end;raise exception 'Expected permission denial';end$$;
create temporary table scrap_proof(payload jsonb);
do $$declare x quality_test.fixtures;y quality_test.fixtures;e uuid;e2 uuid;e3 uuid;missing uuid;unweighted uuid;l uuid;w uuid;r uuid;i uuid;
 s uuid;q uuid;reason uuid;startup uuid:=gen_random_uuid();at_time timestamptz;shift_a uuid;shift_b uuid;standard uuid:=gen_random_uuid();viewer uuid;
 a jsonb;b jsonb;before_state jsonb;after_state jsonb;idx integer;begin
 perform quality_test.make_fixture('scrap-reader','meter',.5,100);
 select * into x from quality_test.fixtures where name='scrap-reader';
 perform public.lean_command(x.factory_id,gen_random_uuid(),'standard',jsonb_build_object('id',standard,'line_id',x.line_id,'product_id',x.product_id,'running_percent',2,'startup_kg',10,'expected_revision',0));
 e:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',x.item_id,'technician',x.technician_id,'good',100,'unfinished',20,'remaining_work','Final inspection','discarded_quantity',0,'scrap_kg',1.2,'input_quantity',0),gen_random_uuid())->>'id')::uuid;
 a:=pg_temp.q_read(x.factory_id,e);
 perform pg_temp.q_assert(a->>'produced_kg'='60.0' and a->>'weight_kg_per_unit'='0.5','Meter mass includes recorded WIP using frozen kg/unit');
 perform pg_temp.q_assert((a->>'running_standard_percent')::numeric=2 and a->>'standard_revision'='1','captured standard revision');
 perform pg_temp.q_assert(a->>'above_running_standard'='false' and (a->>'running_excess_kg')::numeric=0,'exact threshold normal');
 perform pg_temp.q_assert((a->>'startup_allowance_kg')::numeric=0,'shift alone never grants startup allowance');
 perform public.lean_command(x.factory_id,gen_random_uuid(),'standard',jsonb_build_object('id',standard,'line_id',x.line_id,'product_id',x.product_id,'running_percent',20,'startup_kg',100,'expected_revision',1));
 perform pg_temp.q_assert(pg_temp.q_read(x.factory_id,e)=a,'future standard revision does not change historical entry');
 update public.products set unit_weight_kg=9 where id=x.product_id;
 perform pg_temp.q_assert(pg_temp.q_read(x.factory_id,e)=a,'current Product weight cannot rewrite historical mass');
 update public.products set unit_weight_kg=.5 where id=x.product_id;
 select id into s from public.finished_goods_sources where factory_id=x.factory_id and entry_id=e;
 perform public.source_stock_command(x.factory_id,'identify',jsonb_build_object('source',s,'quantity',100,'label','SCRAP-SOURCE','physically_identified',true),'[]',gen_random_uuid());
 select id into reason from public.quality_reasons where factory_id=x.factory_id and not is_other limit 1;
 q:=public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity',1,'reason',reason,'disposition','SCRAP','actual_scrap_kg',.5,'physically_identified',true),gen_random_uuid());
 r:=public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity',1,'reason',reason,'disposition','SCRAP','actual_scrap_kg',.7,'physically_identified',true),gen_random_uuid());
 perform public.quality_command(x.factory_id,'reverse',jsonb_build_object('rejection',r,'physically_present',true,'reason','Isolated fixture reversal'),gen_random_uuid());
 perform public.quality_command(x.factory_id,'reject',jsonb_build_object('source',s,'quantity',2,'reason',reason,'disposition','REWORK','physically_identified',true),gen_random_uuid());
 a:=pg_temp.q_read(x.factory_id,e);
 perform pg_temp.q_assert((a->>'production_scrap_kg')::numeric=1.2 and (a->>'quality_scrap_kg')::numeric=.5,'each permanent rejection counted once; reversed and REWORK excluded');
 perform pg_temp.q_assert((a->>'running_excess_kg')::numeric=.5 and a->>'above_running_standard'='true','Quality Scrap increases excess against historical standard');
 perform pg_temp.q_assert((a->>'produced_kg')::numeric=60 and (public.quality_read(x.factory_id,jsonb_build_object('entry',e))->'rows'->0->>'accepted')::numeric=97,'accepted deduction does not reduce gross mass denominator');
 insert into scrap_proof select public.quality_read(x.factory_id,jsonb_build_object('entry',e));
 -- Read-only historical derivation: no Product-weight fallback or source backfill.
 update public.production_entries set produced_weight_kg=null where factory_id=x.factory_id and id=e;
 b:=pg_temp.q_read(x.factory_id,e);
 perform pg_temp.q_assert((b->>'produced_kg')::numeric=60 and b->>'captured_produced_kg' is null and b->>'mass_source'='HISTORICAL_WEIGHT','missing separate Meter KG derives from captured Good/WIP weight');
 perform pg_temp.q_assert((b->>'running_excess_kg')::numeric=.5 and b->>'above_running_standard'='true','historical derived mass uses the same exact comparison');
 update public.products set unit_weight_kg=9 where id=x.product_id;
 perform pg_temp.q_assert(pg_temp.q_read(x.factory_id,e)=b,'derived mass ignores current Product weight');
 update public.production_entries set produced_weight_kg=60 where factory_id=x.factory_id and id=e;
 update public.products set unit_weight_kg=.5 where id=x.product_id;
 -- Same Product, independent capable line with different approved standard.
 insert into public.production_lines(factory_id,name,code) values(x.factory_id,'Reader line 2','Q2') returning id into l;
 insert into public.work_centers(factory_id,name,code,line_id,category_id)
 select x.factory_id,'Reader extruder 2','Q2',l,category_id from public.work_centers where factory_id=x.factory_id and line_id=x.line_id limit 1 returning id into w;
 insert into public.work_center_capabilities(factory_id,work_center_id,product_id,rate,rate_unit) values(x.factory_id,w,x.product_id,100,'meter');
 perform public.lean_command(x.factory_id,gen_random_uuid(),'standard',jsonb_build_object('id',gen_random_uuid(),'line_id',l,'product_id',x.product_id,'running_percent',4,'startup_kg',0,'expected_revision',0));
 r:=public.create_production_request(x.factory_id,'Reader second line','normal',null,'Local fixture',jsonb_build_array(jsonb_build_object('product_id',x.product_id,'quantity',1000,'unit','meter')));
 select id into i from public.production_orders where factory_id=x.factory_id and request_id=r;
 update public.production_orders set line_id=l,start_time=now()-interval '1 hour',expected_finish=now()+interval '1 hour' where id=i;
 perform public.start_product_item(x.factory_id,i);
 e2:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',l,'item',i,'technician',x.technician_id,'good',100,'discarded_quantity',0,'scrap_kg',1.7,'input_quantity',0),gen_random_uuid())->>'id')::uuid;
 b:=pg_temp.q_read(x.factory_id,e2);
 perform pg_temp.q_assert(b->>'product_id'=a->>'product_id' and b->>'line_id'<>a->>'line_id' and b->>'above_running_standard'='false' and (b->>'running_standard_percent')::numeric=4,'same Product separate actual Line threshold');
 -- Startup history spans two shift identities; earlier declarations are not filtered away.
 perform public.lean_command(x.factory_id,gen_random_uuid(),'standard',jsonb_build_object('id',standard,'line_id',x.line_id,'product_id',x.product_id,'running_percent',2,'startup_kg',10,'expected_revision',2));
 insert into public.production_shifts(factory_id,name,name_ar,created_by) values(x.factory_id,'Reader shift A','وردية أ',x.actor_id) returning id into shift_a;
 insert into public.production_shifts(factory_id,name,name_ar,created_by) values(x.factory_id,'Reader shift B','وردية ب',x.actor_id) returning id into shift_b;
 at_time:=clock_timestamp();
 e2:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',x.item_id,'technician',x.technician_id,'good',100,'discarded_quantity',0,'scrap_kg',8,'startup_kg',8,'startup_id',startup,'startup_at',at_time,'shift',shift_a,'shift_override_reason','Local untimed shift fixture','input_quantity',0),gen_random_uuid())->>'id')::uuid;
 e3:=(public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',x.item_id,'technician',x.technician_id,'good',100,'discarded_quantity',0,'scrap_kg',3,'startup_kg',3,'startup_id',startup,'startup_at',at_time,'shift',shift_b,'shift_override_reason','Local untimed shift fixture','input_quantity',0),gen_random_uuid())->>'id')::uuid;
 a:=pg_temp.q_read(x.factory_id,e3);
 b:=public.quality_read(x.factory_id,jsonb_build_object('mode','board','entry',e3,'shift',shift_b))->'rows'->0->'scrap';
 perform pg_temp.q_assert((pg_temp.q_read(x.factory_id,e2)->>'startup_allowance_kg')::numeric=8 and (a->>'startup_allowance_kg')::numeric=2,'one startup allowance across declarations/shifts');
 perform pg_temp.q_assert((a->>'previous_startup_kg')::numeric=8 and (a->>'cumulative_startup_kg')::numeric=11 and b=a,'entry/shift filter preserves prior startup history');
 perform pg_temp.q_assert(a->>'startup_standard_revision'='3' and (a->>'startup_standard_kg')::numeric=10,'frozen startup revision');
 perform pg_temp.q_assert((a->>'cumulative_startup_kg')::numeric>(a->>'startup_standard_kg')::numeric and a->>'above_running_standard'='false','startup excess separate from running boundary');
 insert into scrap_proof select public.quality_read(x.factory_id,jsonb_build_object('entry',e3));
 for idx in 1..52 loop
  perform public.record_lean_production(x.factory_id,jsonb_build_object('unit_kind','line','production_unit',x.line_id,'item',x.item_id,'technician',x.technician_id,'good',1,'discarded_quantity',0,'scrap_kg',0,'startup_kg',0,'startup_id',startup,'startup_at',at_time,'shift',shift_b,'shift_override_reason','Local untimed shift fixture','input_quantity',0),gen_random_uuid());
 end loop;
 select v->'scrap' into b from jsonb_array_elements(public.quality_read(x.factory_id,'{"mode":"board","page":2}')->'rows') v where v->>'id'=e3::text;
 perform pg_temp.q_assert(b=a,'startup allocation unchanged on later board page');
 perform pg_temp.q_assert(pg_temp.q_read(x.factory_id,x.entry_id)->>'running_standard_percent' is null,'legacy missing snapshot never filled from current standard');
 perform quality_test.make_fixture('scrap-piece','piece',2,100,20);select * into y from quality_test.fixtures where name='scrap-piece';
 b:=pg_temp.q_read(y.factory_id,y.entry_id);perform pg_temp.q_assert((b->>'produced_kg')::numeric=240,'Piece to KG includes new WIP');
 update public.production_entries set produced_weight_kg=null where factory_id=y.factory_id and id=y.entry_id;
 b:=pg_temp.q_read(y.factory_id,y.entry_id);
 perform pg_temp.q_assert((b->>'produced_kg')::numeric=240 and b->>'mass_source'='HISTORICAL_WEIGHT' and b->>'running_standard_percent' is null,'Piece historical derivation works independently of missing standard');
 update public.production_entries set effective_unfinished=null where factory_id=y.factory_id and id=y.entry_id;
 perform pg_temp.q_assert(pg_temp.q_read(y.factory_id,y.entry_id)->>'produced_kg' is null,'unknown new WIP cannot be assumed zero');
 perform quality_test.make_fixture('scrap-missing-weight','meter',null,100);select entry_id into unweighted from quality_test.fixtures where name='scrap-missing-weight';
 perform pg_temp.q_assert((select pg_temp.q_read(factory_id,entry_id)->>'produced_kg' is null from quality_test.fixtures where name='scrap-missing-weight'),'missing weight remains unknown mass');
 perform pg_temp.q_assert((select pg_temp.q_read(factory_id,entry_id)->>'mass_source'='UNAVAILABLE' from quality_test.fixtures where name='scrap-missing-weight'),'unweighted legacy entry never uses current Product weight');
 perform set_config('request.jwt.claim.sub',x.actor_id::text,true);
 -- Local Auth shim and grants exist only in this rollback transaction.
 insert into auth.users(id,email,email_confirmed_at) values(gen_random_uuid(),'scrap-quality-only@isolated.invalid',now()) returning id into viewer;
 insert into public.memberships(factory_id,user_id,display_name,status,is_owner) values(x.factory_id,viewer,'Quality only local fixture','approved',false);
 insert into public.user_permissions(factory_id,user_id,module,action) values(x.factory_id,viewer,'quality','view');
 select jsonb_build_object('balances',(select jsonb_agg(to_jsonb(v) order by product_id,unit) from public.finished_goods_balances v where factory_id=x.factory_id),
  'sources',(select jsonb_agg(to_jsonb(v) order by id) from public.finished_goods_sources v where factory_id=x.factory_id),
  'entries',(select jsonb_agg(to_jsonb(v) order by id) from public.production_entries v where factory_id=x.factory_id),
  'rejections',(select jsonb_agg(to_jsonb(v) order by id) from public.quality_rejections v where factory_id=x.factory_id)) into before_state;
 perform set_config('request.jwt.claim.sub',viewer::text,true);
 execute 'set local role authenticated';
 perform pg_temp.q_assert(pg_temp.q_read(x.factory_id,e3)=a,'real authenticated role with Quality-only grant reads assessment');
 perform pg_temp.q_assert((select count(*)=0 from public.production_entries where factory_id=x.factory_id),'Quality view does not expose direct Orders table');
 perform pg_temp.q_assert((select count(*)=0 from public.lean_startups where factory_id=x.factory_id) and (select count(*)=0 from public.lean_standards where factory_id=x.factory_id),'Quality view does not expose direct Lean tables');
 perform pg_temp.q_error(format('select public.lean_read(%L,''{"mode":"entries"}'')',x.factory_id));
 perform pg_temp.q_error(format('select public.quality_read(%L,''{"mode":"board"}'')',y.factory_id));
 perform pg_temp.q_assert(public.quality_read(x.factory_id,jsonb_build_object('entry',y.entry_id))->'rows'='[]'::jsonb,'foreign entry filter discloses no assessment');
 execute 'reset role';
 select jsonb_build_object('balances',(select jsonb_agg(to_jsonb(v) order by product_id,unit) from public.finished_goods_balances v where factory_id=x.factory_id),
  'sources',(select jsonb_agg(to_jsonb(v) order by id) from public.finished_goods_sources v where factory_id=x.factory_id),
  'entries',(select jsonb_agg(to_jsonb(v) order by id) from public.production_entries v where factory_id=x.factory_id),
  'rejections',(select jsonb_agg(to_jsonb(v) order by id) from public.quality_rejections v where factory_id=x.factory_id)) into after_state;
 perform pg_temp.q_assert(before_state=after_state,'reader does not mutate production/source/stock/rejection state');
 perform pg_temp.q_assert(not has_function_privilege('anon','public.quality_read(uuid,jsonb)','EXECUTE') and has_function_privilege('authenticated','public.quality_read(uuid,jsonb)','EXECUTE'),'RPC execution grants retained');
 perform pg_temp.q_assert((select prosecdef and proconfig=array['search_path=""'] from pg_proc where oid='public.quality_read(uuid,jsonb)'::regprocedure),'SECURITY DEFINER and empty search path retained');
 set constraints all immediate;
 perform pg_temp.q_assert(true,'source/stock deferred conservation holds after all read checks');
end$$;
select 'SCRAP_READER_PROOF='||jsonb_agg(payload)::text from scrap_proof;
rollback;
