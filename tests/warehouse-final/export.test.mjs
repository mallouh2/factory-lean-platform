import test from 'node:test';import assert from 'node:assert/strict';import{createRequire}from'node:module';import{build}from'esbuild';import{NextRequest}from'next/server.js';
import{tablePrintHtml}from'../../src/utils/table-export.mjs';
const require=createRequire(import.meta.url),factory='11111111-1111-4111-8111-111111111111';
async function load(file,mocks={}){const code=(await build({entryPoints:[file],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent',plugins:[{name:'auth',setup(b){b.onResolve({filter:/services\/authorization$/},()=>({path:'fixture:auth',external:true}));}}]})).outputFiles[0].text,m={exports:{}};new Function('require','module','exports',code)(n=>mocks[n]||require(n),m,m.exports);return m.exports;}
const{exportRequest}=await load('src/services/table-export.ts'),{warehouseRequestExportRows,warehouseSupplementReport}=await load('src/services/table-export-warehouse.ts');
test('Warehouse supplementary exports accept only their bounded authorized filter contract',()=>{
 const request={factory,dataset:'warehouse-requests',format:'excel',language:'ar',filters:{department_page:2,kind:'receipt',search:'Pipe'}};
 assert.equal(exportRequest(request).config.permission,'warehouse');assert.equal(exportRequest({...request,dataset:'warehouse-stored-wip',filters:{}}).config.permission,'warehouse');
 for(const filters of[{department_page:0,kind:'',search:''},{department_page:1,kind:'secret',search:''},{department_page:1,kind:'',search:'',private:true}])assert.throws(()=>exportRequest({...request,filters}));
 assert.throws(()=>exportRequest({...request,dataset:'warehouse-stored-wip'}));
});
test('Requests export uses protected readers, exact department page and matching displayed filters',async()=>{
 const calls=[],db={rpc:async(name,args)=>{calls.push({name,args});assert.equal(args.factory,factory);const data=name==='supply_page'?{rows:args.mode==='materials'?[{id:'R',code:'R-1',status:'REQUESTED',item_name:'Pipe',quantity:3,unit:'meter',available_quantity:2}]:[],total:args.mode==='materials'?1:0} :name==='manufactured_receiving_read'?{rows:[],has_more:false} :name==='warehouse_page'?{orders:[]} :null;assert.ok(data);return{data};}};
 const rows=await warehouseRequestExportRows(db,factory,{department_page:2,kind:'issue',search:'Pipe'},'en');assert.equal(rows.length,1);assert.equal(rows[0].row_key,'issue:R');assert.equal(calls.length,1);assert.equal(calls[0].name,'supply_page');assert.equal(calls[0].args.mode,'materials');assert.equal(calls[0].args.page,1);
 assert.equal((await warehouseRequestExportRows(db,factory,{department_page:2,kind:'receipt',search:'Pipe'},'en')).length,0);assert.equal(calls.at(-1).name,'manufactured_receiving_read');assert.equal(calls.at(-1).args.page,0);
});
test('WIP reports contain named classification and exact zero availability without internal keys',()=>{
 for(const language of['en','ar']){const report=warehouseSupplementReport('warehouse-stored-wip',language,[{row_key:'PRIVATE-KEY',name:'Pipe',name_ar:'أنبوب',classification_available:true,missing_operations:[{id:'PRIVATE-ID',name:'Printing',name_ar:'الطباعة'}],unit:'meter',on_hand:'10',reserved:'10',available:'0',held:true}]);
 const html=tablePrintHtml({...report,factory:'Factory',timezone:'UTC',language,timestamp:'2026-10-28T12:00:00Z',filters:'All'});assert.ok(html.includes(language==='ar'?'الطباعة':'Printing'));assert.ok(!html.includes('PRIVATE'));assert.ok(html.includes('10'));assert.ok(html.includes('0'));
 }
});
test('new export requests deny permission before factory or stock data is read',async()=>{
 let reads=0;const route=await load('src/app/api/table-export/route.ts',{'fixture:auth':{verifyOrigin(){},authenticatedClient:async()=>({db:{from(){reads++;throw Error('must not read');}},user:{id:'U'}}),authorize:async()=>{throw Error('permission_denied');}}});
 for(const dataset of['warehouse-stored-wip','warehouse-requests']){const r=await route.POST(new NextRequest('http://localhost/api/table-export',{method:'POST',body:JSON.stringify({factory,dataset,format:'print',language:'en',filters:dataset==='warehouse-requests'?{department_page:1,kind:'',search:''}:{}})}));assert.equal(r.status,403);assert.equal(reads,0);assert.ok(!(await r.text()).includes('Pipe'));}
});
