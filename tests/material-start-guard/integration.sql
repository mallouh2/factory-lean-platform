begin;
set local request.jwt.claim.sub='9bd93b3e-2a88-4d7f-9050-786dfe1c0d73';
create table if not exists qa471.checks(label text);
create or replace function qa471.ok(v boolean,label text)returns void language plpgsql as $$begin if v is distinct from true then raise exception 'Assertion failed: %',label;end if;insert into qa471.checks values(label);end$$;
create or replace function qa471.fails(statement text,message text)returns void language plpgsql as $$begin begin execute statement;exception when others then if sqlerrm=message or sqlstate=message then insert into qa471.checks values('Denied: '||message);return;end if;raise;end;raise exception 'Expected denial: %',message;end$$;
do $$
#variable_conflict use_column
declare x jsonb;f uuid;i uuid;r public.material_requests;v integer;k uuid;payload jsonb;s jsonb;before numeric;readiness jsonb;movement_count integer;w jsonb;shift jsonb;recorded jsonb;entry uuid;g uuid:=gen_random_uuid();mr record;sum_held numeric;begin
 x:=qa471.make_case('integration-normal');f:=(x->>'factory')::uuid;i:=(x->>'item')::uuid;
 perform qa471.ok((select count(*)=3 from public.material_requests where production_item_id=i),'A: recipe generates three correct physical input requests');
 select *into r from public.material_requests where production_item_id=i and material_id=(x->>'additive')::uuid;
 perform qa471.ok(r.quantity=1.6,'B: 100m ×0.8kg/m ×0.02 = exact1.6kg additive');
 s:=private.material_action_context(f,r.id);perform qa471.ok(s->'eligible'->>'RESERVE'='1.6'and s->'eligible'->>'ISSUE'='0','A: authoritative eligible amounts distinguish stock and reservation');
 perform qa471.ok((public.production_material_work(f,'WAREHOUSE',i)->'rows')@>jsonb_build_array(jsonb_build_object('id',r.id,'eligible',s->'eligible')),'A: protected reader exposes authoritative bounds');
 readiness:=public.production_start_readiness(f,i)->'materials';perform qa471.ok(not(readiness->>'ready')::boolean and jsonb_array_length(readiness->'rows')=3,'D: precise missing-material readiness without movements');
 select count(*)into movement_count from public.inventory_transactions where factory_id=f;
 perform qa471.fails(format('select public.start_product_item(%L,%L)',f,i),'production_material_not_ready');
 perform qa471.ok((select status='planned'and actual_start is null from public.production_orders where id=i),'D: failed Start leaves no execution');perform qa471.ok((select count(*)=movement_count from public.inventory_transactions where factory_id=f),'D: failed Start invents no stock movement');
 perform qa471.fails(format('update public.production_orders set status=%L,actual_start=clock_timestamp()where id=%L','active',i),'production_material_not_ready');
 perform qa471.fails(format('select public.production_material_action(%L,%L,%L,%L)',f,'ISSUE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity','1.6','physical_confirmation',true),gen_random_uuid()),'material_quantity');
 select sum(quantity)into before from public.inventory_transactions where factory_id=f and material_id=r.material_id;
 s:=public.production_material_action(f,'RESERVE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity','1.6'),gen_random_uuid());perform qa471.ok(s->>'reserved'='1.6','A/B: fractional reservation succeeds without rounding');
 select revision into v from public.material_requests where id=r.id;k:=gen_random_uuid();payload:=jsonb_build_object('id',r.id,'revision',v,'quantity','0.6','physical_confirmation',true);
 s:=public.production_material_action(f,'ISSUE',payload,k);perform qa471.ok(s->>'issued'='0.6'and s->>'reserved'='1.0'and s->>'consumed'='0','C: first partial handover preserves outstanding reservation and zero consumption');
 perform qa471.ok((select sum(quantity)=before-0.6 from public.inventory_transactions where factory_id=f and material_id=r.material_id),'B/C: Warehouse decreases exact0.6');
 perform qa471.ok(s=public.production_material_action(f,'ISSUE',payload,k),'H: committed fractional issue replays original result');
 perform qa471.ok((select count(*)=1 from public.inventory_transactions where factory_id=f and reference=r.id::text),'H: one physical movement on retry');
 s:=private.material_action_context(f,r.id);perform qa471.ok(s->'eligible'->>'ISSUE'='1'and s->>'production_held'='0.6','C: eligible remainder and Production custody are exact');
 select revision into v from public.material_requests where id=r.id;
 perform qa471.fails(format('select public.production_material_action(%L,%L,%L,%L)',f,'ISSUE',jsonb_build_object('id',r.id,'revision',v,'quantity','1.000001','physical_confirmation',true),gen_random_uuid()),'material_quantity');
 perform public.production_material_action(f,'ISSUE',jsonb_build_object('id',r.id,'revision',v,'quantity','1','physical_confirmation',true),gen_random_uuid());
 perform qa471.ok((select sum(quantity)=before-1.6 from public.inventory_transactions where factory_id=f and material_id=r.material_id),'C: cumulative full handover exact1.6');
 for mr in select *from public.material_requests where production_item_id=i and id<>r.id loop
 perform public.production_material_action(f,'RESERVE',jsonb_build_object('id',mr.id,'revision',mr.revision,'quantity',mr.quantity::text),gen_random_uuid());select revision into v from public.material_requests where id=mr.id;
 perform public.production_material_action(f,'ISSUE',jsonb_build_object('id',mr.id,'revision',v,'quantity',mr.quantity::text,'physical_confirmation',true),gen_random_uuid());end loop;
 perform qa471.ok((public.production_start_readiness(f,i)->'materials'->>'ready')::boolean,'E: full approved recipe physically in Production custody');
 perform public.start_product_item(f,i);perform qa471.ok((select status='active'and actual_start is not null from public.production_orders where id=i),'E: protected Start succeeds');
 perform qa471.ok(not exists(select 1 from private.material_request_progress p join public.material_requests r on r.id=p.request_id where r.production_item_id=i and p.awaiting),'G: starting valid work does not defer material requests');
 shift:=public.production_shift_work(f,null,100);select value into w from jsonb_array_elements(shift->'rows')where value->>'item_id'=i::text;
 perform qa471.ok(w is not null,'J: existing current-shift recording admission works');
 payload:=jsonb_build_object('unit_kind','line','production_unit',x->>'line','item',i,'technician',(select id from public.memberships where factory_id=f and user_id=(x->>'owner')::uuid),'good',20,'scrap_kg',0,'startup_kg',0,'unfinished',0,'remaining_work','','confirm_overproduction',false,'discarded_quantity',0,'recording_context',jsonb_build_object('version',3,'execution_key',w->>'execution_key','occurrence_key',shift->'occurrence'->>'occurrence_key','context_hash',w->>'context_hash','current_shift_quantity_confirmed',true),'output_groups',jsonb_build_array(jsonb_build_object('id',g,'quantity','20','missing_operations','[]'::jsonb)));
 recorded:=public.record_manufactured_output(f,payload,gen_random_uuid());entry:=(recorded->>'entry_id')::uuid;perform qa471.ok(recorded->>'outcome'='COMMITTED','J: partial output records through Manufactured Output');
 for mr in select r.*,p.issued from public.material_requests r join private.material_request_progress p on p.request_id=r.id where r.production_item_id=i loop
 select revision into v from public.material_requests where id=mr.id;k:=gen_random_uuid();payload:=jsonb_build_object('id',mr.id,'revision',v,'quantity',(mr.quantity/5)::text,'entry',entry);s:=public.production_material_action(f,'CONSUME',payload,k);perform qa471.ok(s=public.production_material_action(f,'CONSUME',payload,k),'F/H: measured use retry once for each ingredient');end loop;
 select sum(p.issued-p.consumed)into sum_held from private.material_request_progress p join public.material_requests r on r.id=p.request_id where r.production_item_id=i;
 perform qa471.ok(sum_held=64,'F: measured16kg leaves64kg Production custody');perform qa471.ok((select sum(p.consumed)=16 from private.material_request_progress p join public.material_requests r on r.id=p.request_id where r.production_item_id=i),'F: actual measured consumption explicit and exact');
 perform qa471.ok((select sum(quantity)=before-1.6 from public.inventory_transactions where factory_id=f and material_id=r.material_id),'F: measured use never deducts Warehouse again');
 perform public.finish_product_item(f,i);s:=private.material_action_context(f,r.id);perform qa471.ok(s->>'state'='CLOSED_REVIEW'and s->>'reason'='material_order_reconciliation','G: completed unused custody has an honest review state, not Deferred');
 perform qa471.ok((select count(*)=1 from public.production_entries where order_id=i),'J: owner-style partial recording preserved on Finish');
end$$;
select jsonb_build_object('assertions',count(*),'labels',jsonb_agg(label))from qa471.checks;
rollback;