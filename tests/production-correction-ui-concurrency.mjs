// Creates one identified test recording through the existing writer, never edits old entries.
import fs from 'node:fs';
import path from 'node:path';
import {spawn} from 'node:child_process';
import {randomUUID} from 'node:crypto';
import assert from 'node:assert/strict';
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Phase4B-FIX-runtime-location.txt'),'utf8').trim();
const config=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,''));
assert.equal(config.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(config.databaseHost,'127.0.0.1');
const evidence=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Phase4C-location.txt'),'utf8').trim(),x=config.context;
const quote=value=>"'"+String(value).replaceAll("'","''")+"'";
function sql(text){return new Promise((resolve,reject)=>{const p=spawn(path.join(config.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(config.databasePort),'-U','quality_fixture','-d',config.database,'-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',err='';p.stdout.on('data',c=>out+=c);p.stderr.on('data',c=>err+=c);p.on('close',code=>code?reject(Error(err)):resolve(out.trim().split('\n').filter(Boolean).at(-1)));p.stdin.end(text);});}
assert.equal(await sql("select inet_server_addr()='127.0.0.1'::inet and current_database()='factory_lean_quality_local'"),'t');
const as=(actor,text)=>`begin;set local role authenticated;select set_config('request.jwt.claim.sub',${quote(actor)},true);${text};commit;`;
const payload={unit_kind:'line',production_unit:x.line,item:x.item,technician:x.technician,good:2,discarded_quantity:0,scrap_kg:.125,notes:'Phase4C isolated correction UI fixture'};
const receipt=JSON.parse(await sql(as(x.owner,`select public.record_lean_production(${quote(x.factory)},${quote(JSON.stringify(payload))},${quote(randomUUID())})`)));
const entry=receipt.entry_id||receipt.id;assert.ok(entry);
const context=JSON.parse(await sql(as(x.worker,`select public.production_correction_context(${quote(x.factory)},${quote(entry)})`)));
const proposal={entry,good:'1.5',discarded_quantity:'0',scrap_kg:'0.15',startup_kg:'0',unfinished:'0',remaining_work:'',reason:'Phase4C controlled source allocation concurrency test',expected_revision:Number(context.correction_revision),allocations:[{source_id:null,quantity:'0.5'}]};
const pending=JSON.parse(await sql(as(x.worker,`select public.production_correction_command(${quote(x.factory)},'submit',${quote(JSON.stringify(proposal))},${quote(randomUUID())})`)));assert.equal(pending.status,'PENDING');
const approve=()=>sql(as(x.owner,`select public.production_correction_command(${quote(x.factory)},'approve',${quote(JSON.stringify({id:pending.id}))},${quote(randomUUID())})`)).then(JSON.parse);
const [a,b]=await Promise.all([approve(),approve()]);assert.equal(a.status,'APPROVED');assert.equal(a.correction_id,b.correction_id);
const facts=JSON.parse(await sql(`select jsonb_build_object('corrections',(select count(*) from public.production_entry_corrections where entry_id=${quote(entry)}),'good',effective_good::text,'scrap_kg',effective_scrap_kg::text,'gross',good_quantity::text,'source_credit',(select quantity_credited::text from public.finished_goods_sources where entry_id=e.id)) from public.production_entries e where id=${quote(entry)}`));
assert.equal(facts.corrections,1);assert.equal(Number(facts.good),1.5);assert.equal(Number(facts.gross),2);assert.equal(Number(facts.source_credit),1.5);
fs.writeFileSync(path.join(evidence,'fixture.json'),JSON.stringify({entry,request:pending.id,concurrency:'PASS',facts},null,2));console.log('PASS: concurrent approvals, one correction/source deduction; fixture '+entry);
