// Additional real SQL -> exact transport -> parser correction-page traversal.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {join} from 'node:path';
import {writeFile} from 'node:fs/promises';
import {parseReportingQuery,exactReportingJson,reportingResponse} from '../../src/utils/production-reporting.mjs';
const [bin,port,output]=process.argv.slice(2),quote=x=>"'"+String(x).replaceAll("'","''")+"'";
assert.match(port,/^\d{4,5}$/);
async function sql(text){return new Promise((done,reject)=>{
 const p=spawn(join(bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',port,'-U','quality_fixture','-d','factory_lean_quality_local','-v','ON_ERROR_STOP=1'],{windowsHide:true});let out='',err='';
 p.stdout.on('data',b=>out+=b);p.stderr.on('data',b=>err+=b);p.on('error',reject);p.on('close',code=>{try{assert.equal(code,0,err);done(out.trim());}catch(e){reject(e);}});p.stdin.end(text);
});}
assert.equal(await sql("select current_database()='factory_lean_quality_local' and inet_server_addr()='127.0.0.1'::inet"),'t');
const x=JSON.parse(await sql('select x from reporting_test.context;'));
const entry=await sql(`select entry_id from public.production_entry_corrections where factory_id=${quote(x.factory)} group by entry_id having count(*)>1 order by entry_id limit 1;`);
assert.match(entry,/^[0-9a-f-]{36}$/,'existing operational fixture needs two audited corrections');
const digest=await sql('select reporting_test.digest();');
let cursor=null,total=0,pages=0;const seen=new Set();
do{
 const query=new URLSearchParams({factory:x.factory,reporting_version:'3',mode:'corrections',entry,page_size:'1',...(cursor?{cursor}:{})});
 const args=parseReportingQuery(query);
 const raw=await sql(`begin read only;do $$begin perform set_config('request.jwt.claim.sub',${quote(x.owner)},true);perform set_config('request.jwt.claim.role','authenticated',true);end$$;
 set local role authenticated;select public.production_history(${quote(x.factory)},${quote(JSON.stringify(args.filters))});commit;`);
 const data=reportingResponse(JSON.parse(exactReportingJson(raw)),args);assert.equal(data.rows.length,1);
 const row=data.rows[0];assert.equal(row.entry_id,entry);assert.equal(row.factory_id,x.factory);assert.equal(typeof row.corrected_good,'string');assert.ok(!seen.has(row.id));seen.add(row.id);
 cursor=data.next_cursor;total=data.total;assert.equal(data.complete,cursor===null);pages++;
}while(cursor);
assert.ok(pages>1);assert.equal(seen.size,total);assert.equal(await sql('select reporting_test.digest();'),digest);
await writeFile(join(output,'correction-pages.json'),JSON.stringify({checks:4,pages,total,entry,uniqueAudits:seen.size,beforeDigest:digest,afterDigest:digest,limits:'Real authenticated PostgreSQL and parser, separate from the HTTP scenarios.'},null,2));
console.log(`PASS 4 correction-page checks; ${pages} actual protected SQL pages`);
