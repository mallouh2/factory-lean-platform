import fs from'node:fs';import assert from'node:assert/strict';import{spawnSync}from'node:child_process';import{verifyDatabase,databaseGuard}from'../production-recording-full-app/local-policy.mjs';
const root=fs.readFileSync(process.env.TEMP+'/FactoryLean-Production-End-location.txt','utf8').trim(),c=JSON.parse(fs.readFileSync(root+'/runtime.json'));
const sql=q=>{const r=spawnSync(c.bin+'/psql.exe',['-X','-qAt','-h','127.0.0.1','-p',String(c.databasePort),'-U','quality_fixture','-d',c.database,'-v','ON_ERROR_STOP=1'],{input:q,encoding:'utf8',windowsHide:true});assert.equal(r.status,0,r.stderr);return r.stdout.trim();};
verifyDatabase(c,JSON.parse(sql("select json_build_object('host',inet_server_addr(),'port',inet_server_port(),'database',current_database(),'data',current_setting('data_directory'))")));assert.equal(c.databasePort,55500);
assert.equal(sql("select to_regnamespace('production_end_test')is null"),'t','Fixture already exists: recover it rather than replay setup');
const identity=JSON.parse(sql('select x from wh_final_test.ui_context limit 1'));assert.equal(identity.factory,c.context.factory);assert.equal(identity.owner,c.context.owner);
sql('begin;'+databaseGuard(c)+fs.readFileSync('tests/production-end-recording/fixture.sql','utf8')+'commit;');
const fixtures=JSON.parse(sql('select json_object_agg(label,x)from production_end_test.contexts'));fs.writeFileSync(root+'/fixtures.json',JSON.stringify(fixtures,null,2));console.log({status:'PASS',fixtures:Object.keys(fixtures),databasePort:c.databasePort});
