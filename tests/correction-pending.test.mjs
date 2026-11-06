import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
let response={data:{total:3},loading:false,error:''},calls=[];
globalThis.__pendingRead=(...args)=>{calls.push(args);return response;};
const compiled=await build({entryPoints:['src/hooks/useCorrectionPending.ts'],bundle:true,write:false,platform:'node',format:'cjs',packages:'external',plugins:[{name:'read',setup(b){b.onResolve({filter:/useHistoryData$/},()=>({path:'read',namespace:'fixture'}));b.onLoad({filter:/.*/,namespace:'fixture'},()=>({contents:'export const useHistoryData=(...args)=>globalThis.__pendingRead(...args);'}));}}]});
const m={exports:{}};new Function('require','module','exports',compiled.outputFiles[0].text)(createRequire(import.meta.url),m,m.exports);
test('unauthorized or missing factory never initiates a count request or exposes cached count',()=>{
 // The underlying hook hides cached data when its URL is null; emulate that contract.
 globalThis.__pendingRead=(url,...args)=>{calls.push([url,...args]);return url?response:{data:null,loading:false,error:''};};
 assert.equal(m.exports.useCorrectionPending('factory','worker',false,'1'),null);assert.equal(calls.at(-1)[0],null);
 assert.equal(m.exports.useCorrectionPending('','owner',true,'1'),null);assert.equal(calls.at(-1)[0],null);
});
test('positive count is scoped to actor/factory, with entry/decision refresh identity',()=>{
 response={data:{total:3},loading:false,error:''};assert.equal(m.exports.useCorrectionPending('factory','owner',true,'orders|1'),3);
 assert.deepEqual(calls.at(-1),['/api/production-corrections?factory=factory&pending_count=1','orders|1','owner|factory']);
 m.exports.useCorrectionPending('factory','owner',true,'productionCorrections|2');assert.equal(calls.at(-1)[1],'productionCorrections|2');
});
for(const state of [{data:{total:0}},{data:{total:3},loading:true},{data:{total:3},error:'permissionError'},{data:{total:'3'}},{data:{total:-1}},{data:null}])test('unknown, failed or zero count has no alert '+JSON.stringify(state),()=>{
 response={loading:false,error:'',...state};assert.equal(m.exports.useCorrectionPending('factory','owner',true,'1'),null);
});
