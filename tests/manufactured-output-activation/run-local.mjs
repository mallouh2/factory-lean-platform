// Applies only to an explicitly owned, cold-copied Phase 4B disposable fixture.
// No provisioning, hosted connection, migration-history rewrite or predicate override.
import fs from 'node:fs';import path from 'node:path';import cp from 'node:child_process';import assert from 'node:assert/strict';import{createHash}from'node:crypto';
import{root,c,env,sql,save}from'./local.mjs';
const hash=p=>createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const migration='20261107080452_manufactured_output_safe_activation_v1.sql',m=path.join(c.repo,'supabase/migrations',migration);
const prior=JSON.parse(fs.readFileSync(path.join(c.prior,'baseline.json')));
const historical=prior.inventory.filter(x=>x.path.startsWith('supabase/migrations/'));
assert.equal(historical.length,153);for(const f of historical)assert.equal(hash(path.join(c.repo,f.path)),f.sha256,f.path);
assert.equal(c.baseline.length,90);assert.equal(c.upgrade.length,62);
const resume=process.argv.includes('--continue');
if(resume)assert.equal(JSON.parse(fs.readFileSync(path.join(root,'migration-identity.json'))).sha256,hash(m));
else{
assert.equal(sql("select count(*)from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in('public','private')"),'491');
assert.equal(sql("select to_regclass('private.manufactured_output_activation')is null"),'t');
assert.equal(sql("select count(*)from pg_proc where proname='lean_export_read'"),'0');
save('migration-identity',{migration,sha256:hash(m),historicalHashesVerified:historical.length,baseline:c.baseline,upgrade:c.upgrade,exportReaderApplied:false});
sql(fs.readFileSync(m,'utf8'),'apply-final-candidate');
const defaults=JSON.parse(sql("select json_build_object('rows',(select count(*)from private.manufactured_output_activation),'enabled',(select count(*)from public.factories f where private.manufactured_output_enabled(f.id)),'ordinary_operator_execute',has_function_privilege('authenticated','private.set_manufactured_output_activation(uuid,boolean,bigint,text)','execute'),'service_operator_execute',has_function_privilege('service_role','private.set_manufactured_output_activation(uuid,boolean,bigint,text)','execute'))"));
assert.equal(defaults.rows,0);assert.equal(defaults.enabled,0);assert.equal(defaults.ordinary_operator_execute,false);assert.equal(defaults.service_operator_execute,false);save('default-disabled',defaults);
for(const name of ['fixture.sql','integration.sql'])sql(fs.readFileSync(new URL(name,import.meta.url),'utf8'),name);
save('vertical-slice',{assertions:Number(sql('select count(*)from activation_test.checks')),checks:JSON.parse(sql('select json_agg(t)from activation_test.checks t')),contexts:JSON.parse(sql('select json_agg(t)from activation_test.contexts t')),requests:JSON.parse(sql('select json_agg(t)from activation_test.requests t'))});
}
for(const name of ['acceptance.mjs','concurrency.mjs','http.mjs']){
 const result=cp.spawnSync(process.execPath,[path.join(c.repo,'tests/manufactured-output-activation',name),process.argv[2]],{env,windowsHide:true,encoding:'utf8',timeout:600000,maxBuffer:20e6});
 fs.writeFileSync(path.join(root,'logs',name+'.'+Date.now()+'.log'),result.stdout+result.stderr);console.log(name+': '+result.status+'\n'+result.stdout);assert.equal(result.status,0,result.stderr);
}
// End with all newly activated synthetic factories paused, preserving history.
sql("do $$declare r record;begin for r in select *from private.manufactured_output_activation where enabled loop perform private.set_manufactured_output_activation(r.factory_id,false,r.revision,'Acceptance complete: leave synthetic capability paused');end loop;end$$;",'final-pause');
save('final-gates',JSON.parse(sql('select json_agg(t)from private.manufactured_output_activation t')));
assert.equal(sql('select count(*)from private.manufactured_output_activation where enabled'),'0');
assert.equal(hash(m),JSON.parse(fs.readFileSync(path.join(root,'migration-identity.json'))).sha256);
console.log('PASS exact candidate isolated acceptance; service shutdown remains the operator final cleanup step');
