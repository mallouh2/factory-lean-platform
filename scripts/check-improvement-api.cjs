// Real authenticated HTTP checks; no browser credential automation. Uses testing only.
const fs=require('node:fs'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const env=require('node:util').parseEnv(fs.readFileSync('.env.testing','utf8')),origin='http://localhost:3100';
const server=spawn(process.execPath,['node_modules/next/dist/bin/next','start','--port','3100','--hostname','127.0.0.1'],{env:{...process.env,...env,BUILD_DIRECTORY:'.next-improvements',APP_ORIGIN:origin},stdio:'ignore'});
let cookies='',factory,center;const checks=[];
async function request(path,body){const r=await fetch(origin+path,{method:body?'POST':'GET',headers:{origin,'Content-Type':'application/json',cookie:cookies},body:body?JSON.stringify(body):undefined,signal:AbortSignal.timeout(120000)});const set=r.headers.getSetCookie();if(set.length)cookies=set.map(x=>x.split(';')[0]).join('; ');const j=await r.json();assert.equal(r.status,200,j.error||path);return j;}
async function call(command,args){return (await request('/api/data',{command,args:{factory,...args}})).data;}
(async()=>{try{
 for(let i=0;i<80;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,250));}
 const {owner}=JSON.parse(fs.readFileSync('.env.testing-users.json'));
 await request('/api/auth',{action:'signin',email:owner.email,password:owner.password});checks.push('Testing owner authentication');console.log('PASS: test login');
 let s=await request('/api/data');assert.equal(s.platformAdmin,true);assert.equal(s.factory,null);factory=s.factories.find(f=>f.is_demo).id;assert.ok(s.factories.length);checks.push('Explicit platform landing and factory cards');
 await call('open_platform_factory',{});s=await request('/api/data?factory='+factory);assert.equal(s.factory.id,factory);assert.ok(s.tables.user_permissions.length);checks.push('Audited factory open and scoped snapshot');
 center=await call('save_record',{resource:'centers',id:null,payload:{name:'QA Improvement API',code:'QA-API-'+Date.now().toString(36),type:'manual_station'}});
 await call('change_status',{work_center:center,status:'running'});await call('change_status',{work_center:center,status:'idle'});
 await call('save_record',{resource:'centers',id:center,payload:{archived:true}});
 s=await request('/api/data?factory='+factory);assert.equal(s.tables.status_events.filter(e=>e.work_center_id===center).length,2);checks.push('Existing status and archive features preserve history through HTTP');
 console.log(JSON.stringify({checks}));fs.writeFileSync('test-results/improvement-api.json',JSON.stringify({checks},null,2));
 }catch(e){console.error(String(e.message).split('\n')[0]);process.exitCode=1;}finally{server.kill();}})();
