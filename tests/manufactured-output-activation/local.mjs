// Explicit disposable configuration only. No inherited database credentials.
import fs from 'node:fs';import path from 'node:path';import cp from 'node:child_process';import assert from 'node:assert/strict';
export const c=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
assert.equal(c.marker,'FACTORY_LEAN_PHASE4B3_DISPOSABLE');
export const root=c.root;
assert.ok(path.resolve(c.data).startsWith(path.resolve(root)+path.sep));
assert.equal(c.database,'factory_lean_quality_local');assert.ok(c.port>1024&&c.port!==5432);
export const env={...process.env};for(const key of Object.keys(env))if(/SUPABASE|DATABASE_URL|^PG|VERCEL|TOKEN|SECRET|PASSWORD|API_KEY/i.test(key))delete env[key];
env.PGOPTIONS='-c timezone=UTC -c factorylean.disposable_test=true -c statement_timeout=30000 -c lock_timeout=8000';
env.PGCONNECT_TIMEOUT='3';
export const quote=x=>x===null?'null':"'"+String(x).replaceAll("'","''")+"'";
export const guard=`do $$begin if inet_server_addr()<>'127.0.0.1'::inet or inet_server_port()<>${c.port} or current_database()<>${quote(c.database)} or lower(replace(current_setting('data_directory'),chr(92),'/'))<>${quote(c.data.replaceAll('\\','/').toLowerCase())}then raise exception 'Isolation mismatch';end if;end$$;`;
export function sql(text,label='query'){
 const r=cp.spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(c.port),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{env,windowsHide:true,encoding:'utf8',input:guard+'\n'+text,maxBuffer:40e6,timeout:90000});
 fs.appendFileSync(path.join(root,'acceptance-sql.jsonl'),JSON.stringify({label,code:r.status,sql:text,error:r.stderr})+'\n');
 if(r.status!==0)throw Object.assign(Error(r.stderr.match(/ERROR:\s+([^\r\n]+)/)?.[1]||r.stderr),{detail:r.stderr});return r.stdout.trim();
}
export const claims=actor=>`do $$begin perform set_config('request.jwt.claim.sub',${quote(actor)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;set local role authenticated;`;
export function rpc(actor,name,args){
 assert.match(name,/^[a-z_]+$/);const keys=Object.keys(args);for(const k of keys)assert.match(k,/^[a-z_]+$/);
 const sig=JSON.parse(sql(`select json_build_object('names',proargnames,'types',(select json_agg(format_type(v,null))from unnest(proargtypes)v))from pg_proc where oid=${quote('public.'+name)}::regproc`));
 const parameters=keys.map(k=>{const type=sig.types[sig.names.indexOf(k)];assert.match(type,/^[a-z \[\]]+$/);return `${k}:=(a${['json','jsonb'].includes(type)?'->':'->>'}${quote(k)})::${type}`;});
 return JSON.parse(sql(`begin;${claims(actor)}with args as(select ${quote(JSON.stringify(args))}::jsonb a)select to_jsonb(public.${name}(${parameters.join(',')}))from args;commit;`,name)||'null');
}
export const contexts=()=>Object.fromEntries(JSON.parse(sql('select json_agg(t)from activation_test.contexts t')).map(x=>[x.label,x.x]));
export const context=label=>JSON.parse(sql(`select activation_test.new_context(${quote(label)})`));
export const payload=(x,g=90,w=10)=>JSON.parse(sql(`begin;${claims(x.owner)}select activation_test.payload(${quote(JSON.stringify(x))},${g},${w});commit;`));
export const activate=(x,enabled)=>JSON.parse(sql(`select private.set_manufactured_output_activation(${quote(x.factory)},${enabled},coalesce((select revision from private.manufactured_output_activation where factory_id=${quote(x.factory)}),0),'Isolated authorized acceptance transition')`));
export const revision=o=>Number(sql(`select max(revision)from private.manufactured_output_events where output_id=${quote(o)}`));
export const save=(name,value)=>fs.writeFileSync(path.join(root,name+'.json'),JSON.stringify(value,null,2));
