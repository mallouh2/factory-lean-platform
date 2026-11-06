import fs from 'node:fs';import path from 'node:path';import assert from 'node:assert/strict';import {execFileSync} from 'node:child_process';
export const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Output-P4E-Preview-location.txt'),'utf8').trim();
export const c=JSON.parse(fs.readFileSync(path.join(root,'runtime.json'),'utf8').replace(/^\ufeff/,'')),base='http://127.0.0.1:4221';
assert.equal(c.marker,'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY');assert.equal(c.databaseHost,'127.0.0.1');assert.equal(c.databasePort,55495);assert.equal(c.applicationPort,4221);assert.equal(c.backendPort,4303);
export const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
export function sql(q){try{return execFileSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p','55495','-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1','-v','VERBOSITY=verbose'],{input:q,encoding:'utf8',windowsHide:true,stdio:['pipe','pipe','pipe']}).trim();}catch(e){const raw=String(e.stderr||''),m=raw.match(/ERROR:\s+([A-Z0-9]{5}):\s+([^\r\n]+)/);throw Object.assign(Error(m?.[2]||'local_sql_failure'),{code:m?.[1]||'UNKNOWN'});}}
const identity=JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))"));assert.equal(identity.host,'127.0.0.1');assert.equal(identity.port,55495);assert.equal(identity.database,c.database);assert.equal(path.resolve(identity.data).toLowerCase(),path.resolve(root,'data').toLowerCase());fs.writeFileSync(path.join(root,'independent-endpoint.json'),JSON.stringify(identity,null,2));
export function as(actor,q){return sql(`begin;do $$begin perform set_config('request.jwt.claim.sub',${quote(actor)},true);perform set_config('request.jwt.claim.role','authenticated',true);perform set_config('request.jwt.claims',${quote(JSON.stringify({sub:actor,role:'authenticated'}))},true);end$$;set local role authenticated;${q};commit;`);}
const signatures=new Map();
export function rpc(actor,name,args){
 if(!signatures.has(name))signatures.set(name,JSON.parse(sql(`select json_agg(json_build_object('names',proargnames,'types',(select json_agg(t::regtype::text)from unnest(proargtypes::oid[])t)))from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname=${quote(name)}`)));
 const sig=signatures.get(name)?.find(s=>Object.keys(args).every(k=>s.names.includes(k)));assert.ok(sig,'Original public RPC signature required');
 const params=Object.keys(args).map(k=>{assert.match(k,/^[a-z_]+$/);const type=sig.types[sig.names.indexOf(k)];assert.match(type,/^[a-z .\[\]]+$/);return `${k}:=(a${['json','jsonb'].includes(type)?'->':'->>'}${quote(k)})::${type}`;});
 return JSON.parse(as(actor,`with args as(select ${quote(JSON.stringify(args))}::jsonb a)select to_jsonb(public.${name}(${params.join(',')}))from args`)||'null');
}
export function payload(x,good,wip=0){const r=rpc(x.owner,'production_shift_work',{factory:x.factory,page_size:100}),w=r.rows.find(v=>v.item_id===x.item);assert.ok(w,'Existing protected shift work must contain actual item');const technician=sql(`select id from public.memberships where factory_id=${quote(x.factory)} and user_id=${quote(x.owner)}`);return {unit_kind:'line',production_unit:x.line,item:x.item,technician,good,unfinished:wip,discarded_quantity:0,scrap_kg:0,remaining_work:wip?'Printing remains':'',confirm_overproduction:true,recording_context:{version:3,execution_key:w.execution_key,occurrence_key:r.occurrence.occurrence_key,context_hash:w.context_hash,current_shift_quantity_confirmed:true},output_groups:[...(good?[{id:crypto.randomUUID(),quantity:String(good),missing_operations:[]}]:[]),...(wip?[{id:crypto.randomUUID(),quantity:String(wip),missing_operations:[x.step1]}]:[])]};}
export function output(x,entry){return JSON.parse(sql(`select to_jsonb(h) from private.manufactured_outputs h where h.factory_id=${quote(x.factory)} and h.entry_id=${quote(entry)}`));}
export function revision(x,o){return Number(sql(`select max(revision)from private.manufactured_output_events where factory_id=${quote(x.factory)} and output_id=${quote(o)}`));}
export function audit(x,label){const f=quote(x.factory),p=quote(x.product),i=quote(x.item);const value=JSON.parse(sql(`select jsonb_build_object(
 'factory',${f},'original_item',${i},'label',${quote(label)},
 'balance',(select to_jsonb(b) from public.finished_goods_balances b where factory_id=${f} and product_id=${p} and unit='meter'),
 'demand_received',private.output_demand_received(${f},${i})::text,'demand_remaining',(select greatest(target_quantity-private.output_demand_received(${f},${i}),0)::text from public.production_orders where factory_id=${f} and id=${i}),
 'stored',(select coalesce(sum(warehouse_quantity),0)::text from public.unfinished_lots where factory_id=${f}),
 'unfinished_remaining',(select coalesce(sum(quantity_available),0)::text from public.unfinished_lots where factory_id=${f}),
 'consumed',(select coalesce(sum(input_quantity),0)::text from public.production_entries where factory_id=${f} and input_lot_id is not null),
 'scrap_kg',(select coalesce(sum(effective_scrap_kg),0)::text from public.production_entries where factory_id=${f}),
 'entries',(select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at,e.id),'[]') from public.production_entries e where factory_id=${f}),
 'outputs',(select coalesce(jsonb_agg(to_jsonb(h) order by h.created_at,h.id),'[]')from private.manufactured_outputs h where factory_id=${f}),
 'events',(select coalesce(jsonb_agg(to_jsonb(e) order by e.output_id,e.revision),'[]')from private.manufactured_output_events e where factory_id=${f}),
 'finished_movements',(select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at,m.id),'[]')from public.finished_goods_movements m where factory_id=${f}),
 'unfinished_movements',(select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at,m.id),'[]')from public.unfinished_movements m where factory_id=${f}),
 'lots',(select coalesce(jsonb_agg(to_jsonb(l) order by l.id),'[]')from public.unfinished_lots l where factory_id=${f}),
 'work',(select coalesce(jsonb_agg(to_jsonb(w) order by w.created_at,w.item_id),'[]')from private.manufactured_completion_work w where factory_id=${f}),
 'material_requests',(select coalesce(jsonb_agg(to_jsonb(m) order by m.id),'[]')from public.material_requests m where factory_id=${f}),
 'orders',(select coalesce(jsonb_agg(to_jsonb(o) order by o.id),'[]')from public.production_orders o where factory_id=${f}),
 'contexts',(select count(*) from private.manufactured_output_context where factory_id=${f}))`));fs.mkdirSync(path.join(root,'evidence'),{recursive:true});fs.writeFileSync(path.join(root,'evidence',label+'.json'),JSON.stringify(value,null,2));return value;}
const progressPath=path.join(root,'acceptance.json');
export const progress=fs.existsSync(progressPath)?JSON.parse(fs.readFileSync(progressPath,'utf8')):{steps:{},requests:[],safety:[]};
export const persist=()=>fs.writeFileSync(progressPath,JSON.stringify(progress,null,2));
export async function step(name,fn){if(progress.steps[name]?.status==='PASS'){console.log('RESUME '+name);return progress.steps[name].result;}if(progress.requests.some(r=>r.step===name)&&!progress.resumeApproved?.includes(name))throw Error('Inspect recorded commands before resuming partially executed step: '+name);progress.current=name;persist();try{const result=await fn();progress.steps[name]={status:'PASS',result};persist();console.log('PASS '+name);return result;}catch(e){progress.steps[name]={status:'FAIL',error:e.message,code:e.code};persist();throw e;}}
export function command(actor,name,args){progress.requests.push({step:progress.current,layer:'authenticated PostgreSQL public RPC',actor,name,args,status:'PENDING'});persist();const row=progress.requests.at(-1);try{row.result=rpc(actor,name,args);row.status='COMMITTED';persist();return row.result;}catch(e){row.status='REJECTED';row.error=e.message;row.code=e.code;persist();throw e;}}
export function rejects(label,fn,expected){try{fn();throw Error('Unexpected success: '+label);}catch(e){if(e.message.startsWith('Unexpected success:'))throw e;if(expected)assert.ok(expected.includes(e.message)||expected.includes(e.code),label+': '+e.message);progress.safety.push({label,result:'PASS',code:e.code,reason:e.message});persist();return e;}}
