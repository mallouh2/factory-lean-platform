// Focused continuation after interrupted administration checks. Fictional testing data only.
const fs=require('node:fs'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const {request}=require(process.env.PLAYWRIGHT_MODULE_PATH || 'playwright');
const origin='http://localhost:3100';
const server=spawn(process.execPath,['.next/standalone/server.js'],{env:{...process.env,...require('node:util').parseEnv(fs.readFileSync('.env.testing','utf8')),APP_ORIGIN:origin,PORT:'3100',HOSTNAME:'127.0.0.1'},stdio:'ignore'});
const contexts=[];let owner,factory,managerRole,supportGranted=false;
const call=async(command,args)=>{const r=await owner.post(origin+'/api/data',{timeout:120000,headers:{origin},data:{command,args:{factory,...args}}});const j=await r.json();assert.equal(r.status(),200,command+': '+(j.error||''));return j.data;};
const get=async(client,suffix='')=>{const r=await client.get(origin+'/api/data'+suffix,{timeout:120000});assert.equal(r.status(),200);return r.json();};
(async()=>{try{
 for(let i=0;i<80;i++){try{if((await fetch(origin)).ok)break}catch{}await new Promise(r=>setTimeout(r,250));}
 const credentials=JSON.parse(fs.readFileSync('.env.testing-users.json'));
 const login=async(user)=>{const c=await request.newContext();contexts.push(c);const r=await c.post(origin+'/api/auth',{timeout:120000,headers:{origin},data:{action:'signin',email:user.email,password:user.password}});assert.equal(r.status(),200);return c;};
 owner=await login(credentials.owner);const initial=await get(owner);assert.equal(initial.factory.is_demo,true);factory=initial.factory.id;managerRole=initial.tables.roles.find(r=>r.name==='Factory Manager').id;
 const support=await login(credentials.support);
 await call('set_support_by_email',{email:credentials.support.email,role:managerRole,mode:'temporary',expires_at:new Date(Date.now()+3600000).toISOString()});supportGranted=true;
 assert.equal((await get(support,'?factory='+factory)).factory.id,factory);
 await call('set_support_by_email',{email:credentials.support.email,role:managerRole,mode:'disabled',expires_at:null});supportGranted=false;console.log('PASS: HTTP temporary support by email and disable');
 const center=await call('save_record',{resource:'centers',id:null,payload:{code:'QA-FINAL-'+Date.now().toString(36),name:'Final HTTP test table',type:'assembly_table'}});
 await call('change_status',{work_center:center,status:'running'});await call('change_status',{work_center:center,status:'idle'});
 await call('save_record',{resource:'centers',id:center,payload:{archived:true}});
 const result=await get(owner);assert.equal(result.tables.work_centers.find(c=>c.id===center).archived,true);assert.equal(result.tables.status_events.filter(e=>e.work_center_id===center).length,2);
 const checks=['HTTP support by email, authorized snapshot and disable','HTTP work center archive retains status history'];fs.mkdirSync('test-results',{recursive:true});fs.writeFileSync('test-results/final-http-results.json',JSON.stringify({checks},null,2));console.log(JSON.stringify({checks}));
}catch(e){console.error(String(e.message||e).split('\n')[0]);process.exitCode=1;}finally{
 if(supportGranted)await call('set_support_by_email',{email:'support@nova.example.test',role:managerRole,mode:'disabled',expires_at:null}).catch(()=>{console.error('Support cleanup incomplete');process.exitCode=1;});
 for(const c of contexts)await c.dispose();server.kill();
}})();
