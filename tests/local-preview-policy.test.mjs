import {test} from 'node:test';import assert from 'node:assert/strict';import path from 'node:path';import {tmpdir} from 'node:os';
import {verifyRuntime,verifyDatabase,databaseGuard,initializeOwners,functionMetadata,argumentValue} from './production-recording-full-app/local-policy.mjs';
const c={marker:'FACTORY_LEAN_DISPOSABLE_LOOPBACK_ONLY',root:path.join(tmpdir(),'FactoryLean-policy-test'),database:'factory_lean_quality_local',databaseHost:'127.0.0.1',databasePort:55496,backendPort:4304,applicationPort:4222,context:{owner:'11111111-1111-4111-8111-111111111111',factory:'22222222-2222-4222-8222-222222222222'}};
const env='SUPABASE_URL=http://127.0.0.1:4304\nNEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:4304\n';
test('disposable policy rejects hosted targets, production mode, missing marker and wrong environment',()=>{
 verifyRuntime(c,env,'test');for(const patch of [{marker:''},{databaseHost:'example.supabase.co'},{root:path.parse(c.root).root},{databasePort:4304},{database:'postgres'}])assert.throws(()=>verifyRuntime({...c,...patch},env,'test'));
 assert.throws(()=>verifyRuntime(c,env,'production'));assert.throws(()=>verifyRuntime(c,env.replaceAll('http://127.0.0.1:4304','https://example.supabase.co'),'test'));
});
test('independent endpoint identity and data directory must match the owned cluster',()=>{
 const actual={host:'127.0.0.1',port:55496,database:c.database,data:path.join(c.root,'data')};verifyDatabase(c,actual);
 for(const patch of [{host:'10.0.0.1'},{port:5432},{data:path.join(tmpdir(),'other','data')},{database:'postgres'}])assert.throws(()=>verifyDatabase(c,{...actual,...patch}));
 assert.match(databaseGuard(c),/inet_server_port\(\)<>55496/);assert.match(databaseGuard(c),/data_directory/);
});
test('public RPC discovery mirrors existing SQL execution grants without exposing private functions',()=>{
 const q=functionMetadata('create_sales_order');assert.match(q,/n.nspname='public'/);assert.match(q,/has_function_privilege\('authenticated',p.oid,'EXECUTE'\)/);assert.doesNotMatch(q,/grant |bypassrls/i);
});
test('owner initialization is explicit, factory-scoped, idempotent and never includes restricted identities',async()=>{
 const queries=[];await initializeOwners(async q=>queries.push(q),c);await initializeOwners(async q=>queries.push(q),c);
 assert.equal(queries.length,2);assert.equal(queries[0],queries[1]);assert.match(queries[0],/is_owner and status='approved'/);assert.match(queries[0],/on conflict\(factory_id,user_id,module,action\) do nothing/);assert.doesNotMatch(queries[0],/insert into auth.users|delete|update public.memberships|grant execute/i);
 await assert.rejects(()=>initializeOwners(async()=>assert.fail('unsafe target must not execute SQL'),{...c,marker:''}));
});
test('permission-package and direct-grant arrays use JSON elements rather than PostgreSQL literal text',()=>{
 assert.match(argumentValue('text[]','expected_direct'),/array\(select jsonb_array_elements_text/);
 assert.match(argumentValue('uuid[]','packages'),/then null else array/);
 assert.equal(argumentValue('uuid','factory'),"a->>'factory'");
 assert.equal(argumentValue('jsonb','payload'),"nullif(a->'payload','null'::jsonb)");
});
