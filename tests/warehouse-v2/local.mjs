import fs from 'node:fs';
import {spawnSync} from 'node:child_process';
import {verifyDatabase,databaseGuard,quote} from '../production-recording-full-app/local-policy.mjs';
export {quote};
export const owner=process.argv.includes('--owner');
export const root=fs.readFileSync(process.env.TEMP+(owner?'/FactoryLean-Planning-V3-location.txt':'/FactoryLean-Production-End-location.txt'),'utf8').trim();
export const c=JSON.parse(fs.readFileSync(root+'/runtime.json'));
if(c.marker!=='FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY'||c.databaseHost!=='127.0.0.1'||c.databasePort!==(owner?55496:55500))throw Error('Not the designated disposable database');
export function sql(q){const r=spawnSync(c.bin+'/psql.exe',['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:q,encoding:'utf8',windowsHide:true});if(r.status)throw Error(r.stderr);return r.stdout.trim();}
verifyDatabase(c,JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));
export const guard=databaseGuard(c);
export const as=(actor,q)=>`set local role authenticated;set local request.jwt.claim.sub=${quote(actor)};${q}`;
if(process.argv.includes('--apply')){
 const migration=fs.readFileSync('supabase/migrations/20261101104030_factory_warehouses_v1.sql','utf8');
 sql(guard);sql(migration.replace('begin;',()=>`begin;${guard}`));console.log('Local warehouse schema installed on verified loopback target '+c.databasePort);
}
if(process.argv.includes('--defaults')){sql(`begin;${guard}${as(c.context.owner,`select public.factory_warehouse_command(${quote(c.context.factory)},'DEFAULTS',null,'{}',null,gen_random_uuid());`)}commit;`);console.log('Local factory defaults ensured');}
if(process.argv.includes('--readers')){const m=fs.readFileSync('supabase/migrations/20261101104030_factory_warehouses_v1.sql','utf8');sql(`begin;${guard}`+m.slice(m.indexOf('-- WAREHOUSE RECEIPT READERS')));console.log('Local receipt readers extended');}
if(process.argv.includes('--nonproduction')){
 const m=fs.readFileSync('supabase/migrations/20261101104030_factory_warehouses_v1.sql','utf8'),start=m.indexOf('-- NONPRODUCTION RECEIPT DESTINATIONS'),end=m.indexOf('-- END NONPRODUCTION RECEIPT DESTINATIONS');
 let extra=m.slice(start,end);for(const name of ['factory_warehouses_read','factory_warehouse_command']){const a=m.indexOf('create function public.'+name),b=m.indexOf('\nend$$;',a)+8;extra+=m.slice(a,b).replace('create function','create or replace function');}
 sql(`begin;${guard}`+extra+'commit;');console.log('Local non-production receipt destination adapter installed');
}
