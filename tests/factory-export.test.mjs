import test from 'node:test';
import assert from 'node:assert/strict';
import ExcelJS from 'exceljs';
import { build } from 'esbuild';
import { createRequire } from 'node:module';
import { renderToStaticMarkup } from 'react-dom/server';
import { NextRequest } from 'next/server.js';
import { exportDatasets, readExportTable, readExportPages, factoryWorkbook, safeExportValue } from '../src/utils/factory-export.mjs';
import en from '../src/locales/en.json' with { type: 'json' };
import ar from '../src/locales/ar.json' with { type: 'json' };

const factory = '10000000-0000-0000-0000-000000000001';
const definition = exportDatasets.find(d => d.table === 'products');
function reader(rows, { count = rows.length, error, changeCount = false } = {}) {
  const calls = []; let page = 0;
  return { calls, from(table) {
    const call = { table, order: [] }; calls.push(call);
    return { select(fields, options) { call.fields = fields; call.options = options; return this; },
      eq(field, value) { call.scope = [field, value]; return this; },
      order(field) { call.order.push(field); return this; },
      async range(from, to) { call.range = [from,to]; return { data: rows.slice(from,to+1), error, count: count + (changeCount && page++ ? 1 : 0) }; } };
  } };
}
test('export reads every page with exact factory predicate, explicit fields and deterministic order', async () => {
  const data = Array.from({ length: 1001 }, (_, id) => ({ id, factory_id: factory, name: 'Pipe '+id }));
  const db = reader(data);
  assert.equal((await readExportTable(db, factory, definition)).length, 1001);
  assert.deepEqual(db.calls.map(c => c.range), [[0,499],[500,999],[1000,1499]]);
  for (const call of db.calls) {
    assert.deepEqual(call.scope, ['factory_id',factory]); assert.deepEqual(call.order,['id']);
    assert.equal(call.options.count,'exact'); assert.doesNotMatch(call.fields,/\*|password|token/);
  }
});
test('export rejects wrong-factory rows, unapproved datasets and denied RLS reads', async () => {
  await assert.rejects(readExportTable(reader([{ id: 'x', factory_id: 'another' }]), factory, definition), /permission_denied/);
  await assert.rejects(readExportTable(reader([]),factory,{table:'auth.users',fields:['*']}),/export_invalid/);
  await assert.rejects(readExportTable(reader([],{error:{code:'42501'}}),factory,definition),error=>error.code==='42501');
});
test('protected datasets use the bounded authenticated export RPC and retain row-scope checks', async () => {
  const protectedDefinition=exportDatasets.find(d=>d.table==='bom_versions');
  const calls=[];const rows=Array.from({length:501},(_,id)=>({id,factory_id:factory}));
  const db={rpc:async(name,args)=>{calls.push({name,args});return {data:{rows:rows.slice((args.page-1)*500,args.page*500),total:rows.length}};}};
  assert.equal((await readExportTable(db,factory,protectedDefinition)).length,501);
  assert.deepEqual(calls.map(c=>c.args.page),[1,2]);
  for(const c of calls)assert.deepEqual(c,{name:'factory_export_page',args:{factory,dataset:'bom_versions',page:c.args.page}});
  await assert.rejects(readExportTable({rpc:async()=>({data:{rows:[{id:'x',factory_id:'other'}],total:1}})},factory,protectedDefinition),/permission_denied/);
  await assert.rejects(readExportTable({rpc:async()=>({error:{code:'54000',message:'export_too_large'}})},factory,protectedDefinition),/export_too_large/);
});
test('export fails closed on changing counts, repeated page rows, missing pages and excessive history', async () => {
  const rows = Array.from({length:501},(_,id)=>({id,factory_id:factory}));
  await assert.rejects(readExportTable(reader(rows,{changeCount:true}),factory,definition),/export_changed/);
  await assert.rejects(readExportTable(reader([{id:'same',factory_id:factory},{id:'same',factory_id:factory}]),factory,definition),/export_changed/);
  await assert.rejects(readExportTable(reader([],{count:1}),factory,definition),/export_changed/);
  await assert.rejects(readExportTable(reader(rows),factory,definition,500),/export_too_large/);
});
test('derived readers require complete pages and stable source revision', async () => {
  assert.deepEqual(await readExportPages(async page=>({rows:page===1?[1,2]:[3],total:3,source_revision:4}),{pageSize:2}),[1,2,3]);
  await assert.rejects(readExportPages(async page=>({rows:[page],total:2,source_revision:page})),/export_changed/);
  await assert.rejects(readExportPages(async()=>({rows:[],total:3})),/export_changed/);
});
test('workbook opens with literal user strings, readable factory timestamps, filters and separate units', async () => {
  const buffer = await factoryWorkbook({factory:{id:factory,name:'QA factory',timezone:'Asia/Qatar'},user:{id:'U',email:'qa@example.test'},
    startedAt:'2026-10-05T00:00:00Z',completedAt:'2026-10-05T00:00:01Z',language:'ar',
    sheets:[{sheet:'Production',fields:['name','created_at','quantity','unit','unknown','evidence'],rows:[
      {name:'=HYPERLINK("https://evil.invalid")',created_at:'2026-10-05T01:00:00Z',quantity:100,unit:'meter',unknown:null,evidence:{scrap_kg:5,access_token:'forbidden'}},
      {name:'+SUM(A1:A9)',quantity:20,unit:'piece',unknown:null}]}]});
  const workbook=new ExcelJS.Workbook();await workbook.xlsx.load(buffer);
  const sheet=workbook.getWorksheet('Production');
  assert.equal(sheet.getCell('A2').type,ExcelJS.ValueType.String); assert.equal(sheet.getCell('A2').formula,undefined);
  assert.match(sheet.getCell('B2').value,/04:00:00/); assert.equal(sheet.getCell('C2').value,100);
  assert.equal(sheet.getCell('D2').value,'meter');assert.equal(sheet.getCell('D3').value,'piece');assert.equal(sheet.getCell('E2').value,null);
  assert.doesNotMatch(sheet.getCell('F2').value,/forbidden|access_token/);
  assert.equal(sheet.views[0].ySplit,1); assert.equal(sheet.views[0].rightToLeft,true);assert.ok(sheet.autoFilter);
  assert.equal(workbook.worksheets.length,2);assert.equal(workbook.getWorksheet('Export Metadata').getCell('B6').value,'Asia/Qatar');
});
test('nested credentials and privileged token patterns are removed from exported business text', () => {
  const text=JSON.stringify(safeExportValue({name:'Pipe',password:'pw',nested:{service_role_key:'secret',note:'Bearer abc password=abc postgresql://user:pw@host/db sb_secret_abcdef'}}));
  assert.doesNotMatch(text,/secret|Bearer abc|user:pw|password|service_role_key/);assert.match(text,/redacted/);
});
test('overlong cell values are rejected instead of silently truncated', async () => {
  await assert.rejects(factoryWorkbook({factory:{id:factory,timezone:'UTC'},user:{id:'U'},startedAt:'2026-10-05T00:00:00Z',completedAt:'2026-10-05T00:00:01Z',sheets:[{sheet:'Notes',fields:['note'],rows:[{note:'x'.repeat(32768)}]}]}),/export_cell_too_long/);
});

const require=createRequire(import.meta.url);
const bundle = async path => (await build({entryPoints:[path],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,
  external:['@/services/authorization','@/utils/factory-export.mjs'],logLevel:'silent'})).outputFiles[0].text;
const apiCode = await bundle('src/app/api/factory-export/route.ts');
function load(code, resolve) { const mod={exports:{}};new Function('require','module','exports',code)(name=>resolve?.(name)||require(name),mod,mod.exports);return mod.exports; }
test('HTTP export denies unauthenticated or ungranted callers before reading business data', async () => {
  for(const failure of ['unauthorized','permission_denied']) {
    let reads=0;
    const route=load(apiCode,name=>name==='@/services/authorization'?{verifyOrigin:()=>{},authenticatedClient:async()=>{if(failure==='unauthorized')throw new Error(failure);return {db:{},user:{id:'U'}};},authorize:async()=>{throw new Error(failure);}}:name==='@/utils/factory-export.mjs'?{exportViewModules:[],collectFactoryExport:async()=>{reads++;}}:null);
    const response=await route.POST(new NextRequest('http://localhost:3000/api/factory-export',{method:'POST',body:JSON.stringify({factory})}));
    assert.equal(response.status,failure==='unauthorized'?401:403);assert.equal(reads,0);
  }
});
test('HTTP export enforces origin, all view grants and final export authority before download', async () => {
  for (const scenario of ['origin','partial','revoked','success']) {
    const grants=[];let reads=0,writes=0;
    const route=load(apiCode,name=>name==='@/services/authorization'?{
      verifyOrigin:()=>{if(scenario==='origin')throw new Error('permission_denied');},
      authenticatedClient:async()=>({db:{},user:{id:'U'}}),
      authorize:async(f,module,action)=>{assert.equal(f,factory);grants.push(`${module}:${action}`);
        if((scenario==='partial'&&module==='lean')||(scenario==='revoked'&&reads))throw new Error('permission_denied');},
    }:name==='@/utils/factory-export.mjs'?{
      exportViewModules:['factory','lean'],
      collectFactoryExport:async()=>{reads++;return [{sheet:'Factory',rows:[{id:factory}]}];},
      factoryWorkbook:async()=>{writes++;return new Uint8Array([80,75]);},
    }:null);
    const response=await route.POST(new NextRequest('http://localhost:3000/api/factory-export',{method:'POST',body:JSON.stringify({factory})}));
    assert.equal(response.status,scenario==='success'?200:403);
    assert.equal(reads,['success','revoked'].includes(scenario)?1:0);
    assert.equal(writes,scenario==='success'?1:0);
    if(scenario==='success') {
      assert.deepEqual(grants,['factory:export','factory:view','lean:view','factory:export']);
      assert.equal(response.headers.get('Cache-Control'),'private, no-store');
      assert.match(response.headers.get('Content-Type'),/spreadsheetml/);
      assert.match(response.headers.get('Content-Disposition'),/attachment/);
    }
  }
});
test('export UI is permission-controlled and localized in EN and AR', async () => {
  const component=load(await bundle('src/features/FactoryExport.tsx')).default;
  const React=require('react');
  for(const [lang,strings] of [['en',en],['ar',ar]]) {
    const props={snapshot:{factory:{id:factory}},lang,t:key=>strings[key]||key,can:()=>true};
    const html=renderToStaticMarkup(React.createElement(component,props));
    assert.ok(html.includes(strings.factoryExport));assert.ok(html.includes(strings.factoryExportHelp));
    assert.equal(renderToStaticMarkup(React.createElement(component,{...props,can:()=>false})), '');
  }
});
