// Restart only the canonical app/adapter against an already-running local DB.
// Configuration is explicit; repository .env files cannot supply fallback values.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {spawn,spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
import {fileURLToPath} from 'node:url';
import {verifyRuntime,verifyDatabase} from '../tests/production-recording-full-app/local-policy.mjs';
const require=createRequire(import.meta.url),repo=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const runtimeFile=process.argv[2];assert.ok(runtimeFile,'Explicit existing runtime JSON required');
const c=JSON.parse(fs.readFileSync(runtimeFile,'utf8').replace(/^\ufeff/,''));
assert.equal(path.resolve(c.repo).toLowerCase(),repo.toLowerCase());
assert.equal(path.resolve(c.app).toLowerCase(),repo.toLowerCase());
assert.ok(c.environmentFile,'Explicit preserved local environment file required');
const content=fs.readFileSync(c.environmentFile,'utf8');
const env={...process.env,TEMP:path.dirname(c.root),TMP:path.dirname(c.root)};
for(const k of Object.keys(env))if(/SUPABASE|DATABASE_URL|^PG|VERCEL|TOKEN|SECRET|PASSWORD|API_KEY|^NEXT_PUBLIC_|^APP_|^BUILD_DIRECTORY$|^NODE_ENV$|^__NEXT_PROCESSED_ENV$/.test(k.toUpperCase()))delete env[k];
// Next's own dotenv parser preserves quoting/expansion without evaluating code.
process.env={...env};
const [,parsedEnv]=require('@next/env').processEnv([{path:c.environmentFile,contents:content,env:{}}],undefined,console,true);
Object.assign(env,parsedEnv);
for(const name of ['.env','.env.local','.env.development','.env.development.local']){
 const file=path.join(repo,name);if(!fs.existsSync(file))continue;
 for(const match of fs.readFileSync(file,'utf8').matchAll(/^\s*(?:export\s+)?([\w]+)\s*=/gm))if(!(match[1] in parsedEnv))env[match[1]]='';
}
Object.assign(env,{TEMP:path.dirname(c.root),TMP:path.dirname(c.root),APP_ENV:'development',NEXT_TELEMETRY_DISABLED:'1'});
delete env.NODE_ENV;delete env.__NEXT_PROCESSED_ENV;
verifyRuntime(c,content);
for(const k of ['SUPABASE_URL','NEXT_PUBLIC_SUPABASE_URL'])assert.equal(env[k],`http://127.0.0.1:${c.backendPort}`);
assert.equal(env.SUPABASE_PUBLISHABLE_KEY,'local-preview-public-not-a-hosted-key');
assert.ok(!env.SUPABASE_SERVICE_ROLE_KEY,'No service credential belongs in the app environment');
const r=spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:"select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'));",encoding:'utf8',env,windowsHide:true,timeout:10000});
assert.equal(r.status,0,'Existing local database unavailable');verifyDatabase(c,JSON.parse(r.stdout));
if(process.argv.includes('--preflight')){console.log('Canonical source, explicit local environment and existing database verified.');process.exit(0);}
const adapterOnly=process.argv.includes('--adapter-only');
for(const port of adapterOnly?[c.backendPort]:[c.backendPort,c.applicationPort])await new Promise((resolve,reject)=>{const server=createServer().once('error',reject).listen(port,'127.0.0.1',()=>server.close(resolve));});
const ownedFile=path.join(c.root,'owned-processes-current.json'),owned=JSON.parse(fs.readFileSync(ownedFile));
for(const [label,args] of [
 ['backend',[path.join(repo,'tests/production-recording-full-app/backend.mjs').replaceAll('\\','/'),runtimeFile]],
 ...adapterOnly?[]:[['application',[path.join(repo,'node_modules/next/dist/bin/next').replaceAll('\\','/'),'dev','--webpack','--hostname','127.0.0.1','--port',String(c.applicationPort)]]]]){
 const fd=fs.openSync(path.join(c.root,label+'-current.log'),'a');
 const child=spawn(process.execPath,args,{cwd:repo,env,windowsHide:true,detached:true,stdio:['ignore',fd,fd]});
 child.unref();fs.closeSync(fd);owned[label]=child.pid;
}
fs.writeFileSync(ownedFile,JSON.stringify(owned,null,2));
console.log(`Canonical preview launched: http://127.0.0.1:${c.applicationPort}; existing DB and worker retained.`);
