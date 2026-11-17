import fs from 'node:fs';import cp from 'node:child_process';import path from 'node:path';import assert from 'node:assert/strict';import {randomUUID}from'node:crypto';
import {root,c,env,guard,sql,rpc,quote as q,claims,context,payload,activate,revision,save}from'./local.mjs';
const reports=fs.existsSync(root+'/activation-concurrency.json')?JSON.parse(fs.readFileSync(root+'/activation-concurrency.json')):[];
function connection(name){const child=cp.spawn(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(c.port),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{env,windowsHide:true});let output='',error='',mark;const held=new Promise(r=>mark=r),done=new Promise((resolve,reject)=>{child.stdout.on('data',b=>{output+=b;if(output.includes('ACTIVATION_HELD'))mark();});child.stderr.on('data',b=>error+=b);child.on('error',reject);child.on('close',code=>resolve({code,output,error}));});child.stdin.write(guard+`\nset application_name=${q(name)};select 'BACKEND:'||pg_backend_pid();begin;`);return{child,held,done};}
async function race(label,first,second,expected){
 if(reports.some(r=>r.label===label&&r.passed))return;
 const id=randomUUID(),holder=connection('activation-holder-'+id),waiterName='activation-waiter-'+id;let waiter,timer;
 try{
  holder.child.stdin.write(first+"select 'ACTIVATION_HELD';\n");
  await Promise.race([holder.held,holder.done.then(r=>{throw Error('Holder failed: '+r.error);}),new Promise((_,reject)=>timer=setTimeout(()=>reject(Error('Holder timeout')),15000))]);clearTimeout(timer);
  waiter=connection(waiterName);waiter.child.stdin.end(second+'commit;');let observed;
  for(let n=0;n<80;n++){
   const rows=JSON.parse(sql(`select json_agg(json_build_object('pid',pid,'name',application_name,'state',state,'wait',wait_event,'wait_type',wait_event_type,'blocking',pg_blocking_pids(pid),'xact_start',xact_start))from pg_stat_activity where application_name in(${q('activation-holder-'+id)},${q(waiterName)})`))||[],w=rows.find(x=>x.name===waiterName),h=rows.find(x=>x.name!==waiterName);
   if(w&&h&&w.pid!==h.pid&&w.wait_type==='Lock'&&w.blocking.includes(h.pid)){observed=rows;break;}await new Promise(r=>setTimeout(r,15));
  }
  assert.ok(observed,'Actual blocking overlap required');holder.child.stdin.end('commit;');const result=await Promise.all([holder.done,waiter.done]);assert.equal(result[0].code,0,result[0].error);
  if(expected){assert.notEqual(result[1].code,0);assert.match(result[1].error,expected);}else assert.equal(result[1].code,0,result[1].error);
  assert.ok(result.every(r=>!/deadlock detected|canceling statement due to.*timeout/.test(r.error)));
  reports.push({label,passed:false,observed,result,first,second});save('activation-concurrency',reports);return result;
 }finally{clearTimeout(timer);if(!holder.child.stdin.writableEnded)holder.child.stdin.end('rollback;');if(waiter&&!waiter.child.stdin.writableEnded)waiter.child.stdin.end('rollback;');}
}
function fresh(name){return context(name+'-'+randomUUID().slice(0,8));}
function record(x,p,key){return claims(x.owner)+`select public.record_manufactured_output(${q(x.factory)},${q(JSON.stringify(p))},${q(key)});`;}
function legacy(x,p,key){const plain={...p};delete plain.output_groups;return claims(x.owner)+`select public.record_lean_production(${q(x.factory)},${q(JSON.stringify(plain))},${q(key)});`;}
const gate=(x,on,rev)=>`select private.set_manufactured_output_activation(${q(x.factory)},${on},${rev},'Observed isolated activation race');`;
const stock=x=>sql(`select coalesce((select on_hand from public.finished_goods_balances where factory_id=${q(x.factory)}),0)::text`);
function verified(label,x){const report=reports.findLast(r=>r.label===label);report.conservation=JSON.parse(sql(`select json_build_object('stock',coalesce((select json_agg(t)from public.finished_goods_balances t where factory_id=${q(x.factory)}),'[]'),'outputs',(select count(*)from private.manufactured_outputs where factory_id=${q(x.factory)}),'receipts',(select count(*)from private.receipt_warehouses where factory_id=${q(x.factory)}),'gate',(select to_jsonb(t)from private.manufactured_output_activation t where factory_id=${q(x.factory)}))`));report.passed=true;save('activation-concurrency',reports);console.log('PASS '+label);}
for(const enabledFirst of [true,false]){
 const label=enabledFirst?'Activation wins; waiting legacy client cannot bypass enrollment':'Legacy writer commits before first activation; existing credit preserved';if(reports.some(r=>r.label===label&&r.passed))continue;
 const x=fresh('enable-race'),p=payload(x,2,0),key=randomUUID();
 if(enabledFirst)await race(label,gate(x,true,0),legacy(x,p,key),/output_enrollment_required/);
 else await race(label,legacy(x,p,key),gate(x,true,0));
 assert.equal(stock(x),enabledFirst?'0':'2');assert.equal(sql(`select enabled from private.manufactured_output_activation where factory_id=${q(x.factory)}`),'t');
 verified(label,x);
}
for(const pauseFirst of [true,false]){
 const label=pauseFirst?'Pause wins; waiting manufactured writer posts nothing':'Manufactured writer commits once; pause waits';if(reports.some(r=>r.label===label&&r.passed))continue;
 const x=fresh('pause-race');activate(x,true);const p=payload(x,2,0),key=randomUUID();
 if(pauseFirst)await race(label,gate(x,false,1),record(x,p,key),/output_paused/);
 else await race(label,record(x,p,key),gate(x,false,1));
 assert.equal(stock(x),'0');assert.equal(sql(`select count(*)from private.manufactured_outputs where factory_id=${q(x.factory)}`),pauseFirst?'0':'1');assert.equal(sql(`select enabled from private.manufactured_output_activation where factory_id=${q(x.factory)}`),'f');
 if(!pauseFirst)assert.equal(rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:p,request_id:key}).replayed,true);
 verified(label,x);
}
for(const same of [true,false]){
 const label=same?'Concurrent identical physical receipt credits once':'Competing physical receipts reject stale revision';if(reports.some(r=>r.label===label&&r.passed))continue;
 const x=fresh('receipt-race');activate(x,true);const p=payload(x),r=rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:p,request_id:randomUUID()}),h=JSON.parse(sql(`select to_jsonb(t)from private.manufactured_outputs t where entry_id=${q(r.entry_id)}`)),groups=h.recorded_groups.map(g=>({...g,released:g.quantity}));
 rpc(x.worker,'manufactured_output_command',{factory:x.factory,operation:'QUALITY',target:h.id,payload:{groups,rejected:'0',total:'100',actual_rejected_kg:'0',reason:'Concurrent physical receipt fixture inspection'},expected_revision:revision(h.id),request_id:randomUUID()});
 const g=groups.find(g=>!g.missing_operations.length),body={group_id:g.id,quantity:'30',warehouse_id:x.finished_warehouse,physical_confirmation:true},rev=revision(h.id),key=randomUUID(),receive=k=>claims(x.viewer)+`select public.receive_manufactured_output(${q(x.factory)},${q(h.id)},${q(JSON.stringify(body))},${rev},${q(k)});`;
 await race(label,receive(key),receive(same?key:randomUUID()),same?null:/output_revision/);
 assert.equal(stock(x),'30');assert.equal(sql(`select count(*)from private.receipt_warehouses where factory_id=${q(x.factory)}`),'1');assert.equal(sql(`select private.output_received(${q(x.factory)},${q(h.id)},${q(g.id)})::text`),'30');
 verified(label,x);
}
{
 const label='Quality amendment wins; waiting receipt rejects stale entitlement';
 if(!reports.some(r=>r.label===label&&r.passed)){
  const x=fresh('quality-receipt-race');activate(x,true);const r=rpc(x.owner,'record_manufactured_output',{factory:x.factory,payload:payload(x),request_id:randomUUID()}),h=JSON.parse(sql(`select to_jsonb(t)from private.manufactured_outputs t where entry_id=${q(r.entry_id)}`)),groups=h.recorded_groups.map(g=>({...g,released:g.quantity}));
  rpc(x.worker,'manufactured_output_command',{factory:x.factory,operation:'QUALITY',target:h.id,payload:{groups,rejected:'0',total:'100',actual_rejected_kg:'0',reason:'Initial inspection before actual receipt race'},expected_revision:revision(h.id),request_id:randomUUID()});
  const g=groups.find(g=>!g.missing_operations.length),rev=revision(h.id),amended=groups.map(a=>a.id===g.id?{...a,quantity:'85',released:'85'}:a),body={groups:amended,rejected:'5',total:'100',actual_rejected_kg:'2.5',reason:'Independent Quality amendment during physical receipt'};
  await race(label,claims(x.worker)+`select public.manufactured_output_command(${q(x.factory)},'QUALITY',${q(h.id)},${q(JSON.stringify(body))},${rev},${q(randomUUID())});`,claims(x.viewer)+`select public.receive_manufactured_output(${q(x.factory)},${q(h.id)},${q(JSON.stringify({group_id:g.id,quantity:'30',warehouse_id:x.finished_warehouse,physical_confirmation:true}))},${rev},${q(randomUUID())});`,/output_revision/);
  assert.equal(stock(x),'0');assert.equal(sql(`select count(*)from private.receipt_warehouses where factory_id=${q(x.factory)}`),'0');assert.equal(revision(h.id),rev+1);verified(label,x);
 }
}
console.log('PASS '+reports.filter(r=>r.passed).length+' observed activation/receipt races');
