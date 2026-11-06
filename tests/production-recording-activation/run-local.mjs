// A fresh disposable database plus one real-app browser smoke. Never loads repository .env.local.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import net from 'node:net';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const repo=process.cwd(),root=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Activation-location.txt'),'utf8').trim();
assert.ok(path.resolve(root).startsWith(path.resolve(os.tmpdir())+path.sep));
const bin=path.join(os.tmpdir(),'FactoryLean-Shift-M1-Runtime-20261018','pgsql','bin'),data=path.join(root,'data'),app=path.join(root,'app');
const port=55479,applicationPort=4211,backendPort=4293;
const resume=process.argv.includes('--resume');assert.equal(fs.existsSync(data),resume,'Use a fresh evidence directory, or explicitly resume an interrupted test');
for(const port of [55479,4211,4293])await new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',reject);s.listen(port,'127.0.0.1',()=>s.close(resolve));});
function run(exe,args,input,log,cwd=repo){return new Promise((resolve,reject)=>{
 if(exe.endsWith('pg_ctl.exe')){const fd=fs.openSync(path.join(root,log),'w'),c=spawn(exe,args,{cwd,windowsHide:true,stdio:['ignore',fd,fd]});c.on('error',reject);c.on('exit',code=>{fs.closeSync(fd);code?reject(Error(fs.readFileSync(path.join(root,log),'utf8'))):resolve('');});return;}
 const c=spawn(exe,args,{cwd,windowsHide:true});let output='';c.stdout.on('data',b=>output+=b);c.stderr.on('data',b=>output+=b);c.on('error',reject);c.on('close',code=>{if(log)fs.writeFileSync(path.join(root,log),output);code?reject(Error(output.slice(-3500))):resolve(output.trim());});c.stdin.end(input);
});}
const sql=q=>run(path.join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(port),'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],q);
const include=f=>"\\i '"+path.resolve(f).replaceAll('\\','/')+"'";
const file=async(f,log)=>{try{const result=await sql(include(f));fs.writeFileSync(path.join(root,log),result);return result;}catch(e){fs.writeFileSync(path.join(root,log),e.message);throw e;}};
const children=[];let started=false;
const background=(exe,args,cwd,log)=>{const fd=fs.openSync(path.join(root,log),'w'),c=spawn(exe,args,{cwd,windowsHide:true,stdio:['ignore',fd,fd]});children.push(c);fs.closeSync(fd);return c;};
const functions="select jsonb_object_agg(p.oid::regprocedure::text,jsonb_build_object('definition',pg_get_functiondef(p.oid),'acl',p.proacl)) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f'";
try{
 if(!resume){await run(path.join(bin,'initdb.exe'),['-D',data,'-U','quality_fixture','--encoding=UTF8','--locale=C','--auth=trust'],undefined,'initdb.txt');fs.appendFileSync(path.join(data,'postgresql.conf'),"\ntimezone='UTC'\n");}
 await run(path.join(bin,'pg_ctl.exe'),['-D',data,'-l',path.join(root,'postgres.log'),'-o',`-h 127.0.0.1 -p ${port}`,'-w','start'],undefined,'start.txt');started=true;
 if(!resume)await run(path.join(bin,'createdb.exe'),['-h','127.0.0.1','-p',String(port),'-U','quality_fixture','factory_lean_quality_local']);
 assert.equal(await sql("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
 if(resume&&(!fs.existsSync(path.join(root,'boundary.txt'))||!/^\d+$/.test(fs.readFileSync(path.join(root,'boundary.txt'),'utf8').trim())))console.log(await file('tests/production-recording-activation/boundary.sql','boundary.txt'));
 if(!resume){await file('tests/quality/local-bootstrap.sql','bootstrap.txt');
 const migrations=fs.readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')&&f!=='20261006072000_factory_export_reader.sql').sort();assert.equal(migrations.length,99);
 for(const f of migrations.slice(0,-1)){
  if(f==='20261010061827_quality_source_stock_v1.sql')await file('tests/quality/pre-source-fixture.sql','pooled-fixture.txt');
  await sql(include('supabase/migrations/'+f));
 }
 const before=JSON.parse(await sql(functions));await file('supabase/migrations/'+migrations.at(-1),'migration.txt');const after=JSON.parse(await sql(functions));
 const changed=Object.keys(before).filter(k=>JSON.stringify(before[k])!==JSON.stringify(after[k]));assert.deepEqual(changed,['production_shift_work(uuid,jsonb,integer)']);
 assert.deepEqual(before[changed[0]].acl,after[changed[0]].acl);fs.writeFileSync(path.join(root,'contracts.json'),JSON.stringify({required_migrations:migrations.length,unchanged_functions:Object.keys(before).length-1,changed,acl_preserved:true},null,2));
 await file('tests/maintenance-planning/fixture.sql','fixture.txt');await file('tests/production-late-recording/fixture.sql','late-fixture.txt');
 console.log(await file('tests/production-recording-activation/capability.sql','capability.txt'));
 await file('tests/production-recording-activation/boundary.sql','boundary.txt');
 await file('tests/production-recording-full-app/seed.sql','browser-seed.txt');}
 const context=JSON.parse(await sql('select x from local_preview.context'));
 // This fresh synthetic technician needs Floor view to reach its recording entry point.
 // Fixture setup only; no approve grant or change to any retained/hosted identity.
 await sql(`insert into public.user_permissions(factory_id,user_id,module,action)values('${context.factory}','${context.worker}','lines','view') on conflict do nothing`);
 fs.mkdirSync(app,{recursive:true});for(const f of ['src','public','scripts'])fs.cpSync(f,path.join(app,f),{recursive:true});
 for(const f of ['package.json','package-lock.json','tsconfig.json','next.config.ts','next-env.d.ts','postcss.config.mjs'])if(fs.existsSync(f))fs.copyFileSync(f,path.join(app,f));
 if(!resume)fs.symlinkSync(path.join(repo,'node_modules'),path.join(app,'node_modules'),'junction');
 fs.writeFileSync(path.join(app,'.env.local'),`APP_ENV=development\nAPP_ORIGIN=http://127.0.0.1:${applicationPort}\nSUPABASE_URL=http://127.0.0.1:${backendPort}\nSUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key\nNEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:${backendPort}\nNEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=local-preview-public-not-a-hosted-key\nNEXT_TELEMETRY_DISABLED=1\n`);
 const runtime={marker:'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY',root,app,bin,databaseHost:'127.0.0.1',databasePort:port,database:'factory_lean_quality_local',applicationPort,backendPort,context};
 fs.writeFileSync(path.join(root,'runtime.json'),JSON.stringify(runtime,null,2));
 if(!resume){await run(process.execPath,[path.join(repo,'node_modules/typescript/bin/tsc'),'--noEmit','--incremental','false'],undefined,'typescript.txt',app);console.log('PASS TypeScript');
 await run(process.execPath,[path.join(repo,'node_modules/next/dist/bin/next'),'build','--webpack'],undefined,'build.txt',app);console.log('PASS isolated optimized build');}
 background(process.execPath,[path.join(repo,'tests/production-recording-full-app/backend.mjs'),path.join(root,'runtime.json')],repo,'backend.txt');
 background(process.execPath,[path.join(repo,'node_modules/next/dist/bin/next'),'dev','--webpack','--hostname','127.0.0.1','--port',String(applicationPort)],app,'next.txt');
 for(const url of [`http://127.0.0.1:${backendPort}/health`,`http://127.0.0.1:${applicationPort}`]){let ok=false;for(let i=0;i<60;i++){try{if((await fetch(url)).ok){ok=true;break;}}catch{}await new Promise(r=>setTimeout(r,500));}assert.ok(ok,'Server ready '+url);}
 console.log(await run(process.execPath,['tests/production-recording-activation/browser.mjs',root,...(process.argv.includes('--finish-mobile')?['--finish-mobile']:[])],undefined,'browser.txt'));
 assert.equal(await sql('select count(*) from private.production_recording_v3_activation where enabled or schema_contract_version<>0'),'0');
 fs.writeFileSync(path.join(root,'summary.json'),JSON.stringify({sql_checks:Number(await sql('select count(*) from late_test.checks')),gates_disabled:true,typescript:true,build:true,browser:true},null,2));
}finally{
 for(const c of children)c.kill();
 if(started)await run(path.join(bin,'pg_ctl.exe'),['-D',data,'-m','fast','-w','stop'],undefined,'stop.txt');
 // Preserve test data/results for review; no deletion or retained-preview process changes.
}
