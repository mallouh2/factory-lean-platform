// Reuse portable binaries and original ordered migrations. Tests only in a fresh disposable localhost database.
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import {spawn} from 'node:child_process';
import assert from 'node:assert/strict';
const evidence=fs.readFileSync(path.join(os.tmpdir(),'FactoryLean-Phase4D-location.txt'),'utf8').trim();
const r=JSON.parse(fs.readFileSync(path.join(evidence,'runtime-safe.json'))),port=55478;
assert.equal(r.databasePort,55476);assert.equal(r.database,'factory_lean_quality_local');
const out=path.join(evidence,'sql'),data=path.join(out,'data');fs.mkdirSync(out,{recursive:true});
function run(exe,args,input,log){return new Promise((resolve,reject)=>{if(exe.endsWith('pg_ctl.exe')){const target=path.join(out,log||'pg-ctl.txt'),fd=fs.openSync(target,'w');const child=spawn(exe,args,{windowsHide:true,stdio:['ignore',fd,fd]});child.on('error',reject);child.on('exit',code=>{fs.closeSync(fd);const result=fs.readFileSync(target,'utf8');code?reject(Error(result)):resolve(result.trim());});return;}const child=spawn(exe,args,{windowsHide:true});let text='',error='';child.stdout.on('data',b=>text+=b);child.stderr.on('data',b=>error+=b);child.on('error',reject);child.on('close',code=>{if(log)fs.writeFileSync(path.join(out,log),text+error);code?reject(Error((error||text).slice(-5000))):resolve(text.trim());});child.stdin.end(input);});}
const bin=name=>path.join(r.bin,name+'.exe'),args=['-X','-qAt','-h','127.0.0.1','-p',String(port),'-U','quality_fixture','-d',r.database,'-v','ON_ERROR_STOP=1'];
const sql=(q,log)=>run(bin('psql'),args,q,log),file=(f,log)=>run(bin('psql'),[...args,'-f',path.resolve(f)],undefined,log);
let started=false;
try{
 const net=await import('node:net');await new Promise((resolve,reject)=>{const s=net.createServer();s.once('error',reject);s.listen(port,'127.0.0.1',()=>s.close(resolve));});
 const identity=await run(bin('psql'),['-X','-qAt','-h','127.0.0.1','-p','55476','-U','quality_fixture','-d',r.database,'-c',"select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"],undefined);assert.equal(identity,'t');
 await run(bin('initdb'),['-D',data,'-U','quality_fixture','--encoding=UTF8','--locale=C','--auth=trust'],undefined,'initdb.txt');
 fs.appendFileSync(path.join(data,'postgresql.conf'),"\ntimezone='UTC'\n");
 await run(bin('pg_ctl'),['-D',data,'-l',path.join(out,'postgres.log'),'-o',`-h 127.0.0.1 -p ${port}`,'-w','start'],undefined,'start.txt');started=true;
 await run(bin('createdb'),['-h','127.0.0.1','-p',String(port),'-U','quality_fixture',r.database]);
 await file('tests/quality/local-bootstrap.sql','bootstrap.txt');
 const migrations=fs.readdirSync('supabase/migrations').filter(f=>f.endsWith('.sql')&&f!=='20261006072000_factory_export_reader.sql').sort();assert.equal(migrations.length,98);
 const include=f=>"\\i '"+path.resolve(f).replaceAll('\\','/')+"'";
 const chain=migrations.flatMap(f=>[...(f==='20261010061827_quality_source_stock_v1.sql'?[include('tests/quality/pre-source-fixture.sql')]:[]),include('supabase/migrations/'+f)]).join('\n');
 await sql(chain,'migrations.txt');
 await file('tests/maintenance-planning/fixture.sql','base-fixture.txt');
 await file('tests/production-recording-full-app/seed.sql','preview-fixture.txt');
 const steps=[
 ['tests/production-correction-ui.sql','context-ui.txt'],
 ['tests/production-late-recording/fixture.sql','late-fixture.txt'],
 ['tests/production-late-recording/writer.test.sql','writer.txt'],
 ['tests/production-late-recording/boundary.test.sql','deadline.txt'],
 ['tests/production-corrections/before.sql','correction-before.txt'],
 ['tests/production-corrections/fixture.sql','correction-fixture.txt'],
 ['tests/production-corrections/policy.test.sql','correction-policy.txt'],
 ['tests/production-corrections/security.test.sql','correction-security.txt'],
 ['tests/production-reporting/seed.sql','reporting-seed.txt'],
 ['tests/production-consumers/before.sql','consumer-before.txt'],
 ['tests/production-consumers/consumers.test.sql','consumer-quantities.txt'],
 ['tests/production-consumers/initiative.test.sql','consumer-saved.txt'],
 ];
 for(const [f,log]of steps){await file(f,log);console.log('PASS '+f);}
 await run(process.execPath,['tests/production-corrections/concurrency.mjs',r.bin,String(port),out],undefined,'concurrency.txt');console.log('PASS three actual correction concurrency races');
 await file('tests/production-recording-phase4d/my-requests.sql','my-requests.txt');
 const result=await sql("select jsonb_build_object('late_checks',(select count(*) from late_test.checks),'correction_checks',(select count(*) from correction_test.checks),'consumer_checks',(select count(*) from m3c_test.checks),'recording_enabled',(select count(*) from private.production_recording_v3_activation where enabled),'maintenance_enabled',(select count(*) from private.maintenance_planning_activation where enabled))",'summary.json');
 assert.equal(JSON.parse(result).recording_enabled,0);assert.equal(JSON.parse(result).maintenance_enabled,0);console.log('PASS '+result);
}finally{
 if(started)await run(bin('pg_ctl'),['-D',data,'-m','fast','-w','stop'],undefined,'stop.txt');
 // Keep scripts, results and diagnostic data. No retained preview process is stopped.
}
