// Local disposable read-metadata migration only. No operational business commands.
import fs from'node:fs';import path from'node:path';import{spawnSync}from'node:child_process';import assert from'node:assert/strict';import{verifyRuntime,verifyDatabase,databaseGuard}from'../production-recording-full-app/local-policy.mjs';
const root=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-Planning-V3-location.txt'),'utf8').trim(),qa=fs.readFileSync(path.join(process.env.TEMP,'FactoryLean-OperationalUX-SQL-location.txt'),'utf8').trim(),result=[];
const file='supabase/migrations/20261028133240_warehouse_receipt_operation_labels_v1.sql';
for(const runtime of[path.join(qa,'warehouse-final-runtime.json'),path.join(root,'runtime.json')]){
 const c=JSON.parse(fs.readFileSync(runtime));assert.ok([55496,55498].includes(c.databasePort));verifyRuntime(c,fs.readFileSync(path.join(c.app,'.env.local'),'utf8'));
 function sql(q){const r=spawnSync(path.join(c.bin,'psql.exe'),['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:q,encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
 verifyDatabase(c,JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));
 function digest(){return sql(`do $$declare x record;v text;d text:='';begin for x in select n.nspname,c.relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where c.relkind='r'and n.nspname in('public','private','auth')order by n.nspname,c.relname loop execute format('select md5(coalesce(string_agg(to_jsonb(t)::text,chr(10)order by to_jsonb(t)::text),''''))from %I.%I t',x.nspname,x.relname)into v;d:=d||x.nspname||'.'||x.relname||v;end loop;perform set_config('test.operational_digest',md5(d),false);end$$;select current_setting('test.operational_digest');`);}
 const before=digest();sql(fs.readFileSync(file,'utf8').replace(/^begin;/,()=>'begin;'+databaseGuard(c)));assert.equal(digest(),before,'Read metadata migration must not change operational data');result.push({port:c.databasePort,operationalDigestUnchanged:true,file});
}
fs.writeFileSync(path.join(root,'warehouse-final','label-reader.json'),JSON.stringify(result,null,2));console.log(result);
