const fs=require('fs'),assert=require('assert/strict'),l=require('./qa-local.cjs'),x=require('./qa-factory.json');
const prefix=fs.readFileSync(__dirname+'/integration.sql','utf8').split('do $$\n#variable_conflict')[0];
const test=`do $$declare c jsonb;other jsonb;r public.material_requests;p private.material_request_progress;z uuid;s jsonb;begin
c:=qa471.make_case('identity-negative');other:=qa471.make_case('identity-other');
select *into r from public.material_requests where production_item_id=(c->>'item')::uuid and material_id=(c->>'additive')::uuid;
perform public.production_material_action(r.factory_id,'RESERVE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity','1.6'),gen_random_uuid());
select *into p from private.material_request_progress where request_id=r.id;
update public.inventory_reservations set order_id=(other->>'item')::uuid where id=p.reservation_id;
s:=private.material_action_context(r.factory_id,r.id);perform qa471.ok(s->>'reason'='material_custody_review'and s->'eligible'->>'ISSUE'='0','Wrong-order reservation fails closed');
select revision into r.revision from public.material_requests where id=r.id;
perform qa471.fails(format('select public.production_material_action(%L,%L,%L,%L)',r.factory_id,'ISSUE',jsonb_build_object('id',r.id,'revision',r.revision,'quantity','1.6','physical_confirmation',true),gen_random_uuid()),'material_preparation_unavailable');
update public.inventory_reservations set order_id=(c->>'item')::uuid,material_id=(c->>'raw')::uuid where id=p.reservation_id;
s:=private.material_action_context(r.factory_id,r.id);perform qa471.ok(s->>'reason'='material_custody_review'and s->'eligible'->>'ISSUE'='0','Wrong-material reservation fails closed');
perform qa471.ok(not exists(select 1 from public.inventory_transactions where reference=r.id::text),'Invalid reservation never makes physical movement');
end$$;select jsonb_build_object('assertions',count(*),'labels',jsonb_agg(label))from qa471.checks;rollback;`;
l.save('extra-sql-results',JSON.parse(l.sql(prefix+test)));
const c=JSON.parse(l.sql("select qa471.make_case('snapshot-negative')"));for(const statement of [`select public.start_product_item(${l.q(c.factory)},${l.q(c.item)})`,`update public.production_orders set status='active',actual_start=clock_timestamp()where id=${l.q(c.item)}`]){assert.throws(()=>l.sql(`begin isolation level repeatable read;set local request.jwt.claim.sub=${l.q(x.owner)};${statement};rollback;`),/execution_readiness_stale/);}console.log('PASS four reservation identity assertions and two repeatable-read admission denials');
