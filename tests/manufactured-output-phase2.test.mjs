import test from 'node:test';
import assert from 'node:assert/strict';
import {outputGroups,outputTotal,inspectionValid} from '../src/utils/manufactured-output.mjs';
import {recordingBody} from '../src/utils/production-recording-intent.mjs';
const op=[{id:'print'},{id:'cut'}],g=(quantity,operations=[],id='a')=>({id,quantity,missing_operations:operations,released:'0'});
test('100 finished and split 90 + 6 + 4 with canonical operation sets',()=>{
 assert.equal(outputTotal(outputGroups('100',[],op,'meter','f')),'100');
 const groups=outputGroups('90',[g('6',['print']),g('4',['print','cut'],'b')],op,'meter','f');
 assert.equal(outputTotal(groups),'100');assert.deepEqual(groups[2].missing_operations,['cut','print']);
 assert.deepEqual(groups,outputGroups('90',[g('6',['print']),g('4',['cut','print'],'b')],op,'meter','f'));
});
test('exact fractions and Arabic decimal input remain exact',()=>{
 assert.equal(outputTotal(outputGroups('٠٫١٢٣٤٥٦٧٨٩٠١٢٣٤٥٦٧٨٩',[g('0.0000000000000000001',['print'])],op,'meter','f')),'0.123456789012345679');
});
test('duplicate, missing, invalid operations and fractional pieces reject',()=>{
 for(const operations of [[],['print','print'],['other']])assert.throws(()=>outputGroups('1',[g('1',operations)],op,'meter','f'));
 assert.throws(()=>outputGroups('1.2',[],op,'piece','f'));
});
test('Quality conserves total, rejects excess release and permits partial release/reclassification',()=>{
 const groups=[{...g('90',[]),released:'40'},g('10',['print'],'b')];
 assert.equal(inspectionValid(groups,'0','100','meter',op),true);
 assert.equal(inspectionValid([{...groups[0],released:'91'},groups[1]],'0','100','meter',op),false);
 assert.equal(inspectionValid(groups,'1','100','meter',op),false);
 assert.equal(inspectionValid([g('85',[]),g('10',['cut'],'b')],'5','100','meter',op),true);
});
test('new intent uses separate writer; legacy body remains legacy',()=>{
 const id='11111111-1111-4111-8111-111111111111';
 assert.equal(JSON.parse(recordingBody(id,id,{good:'1'})).command,'record_lean_production');
 const body=recordingBody(id,id,{good:'0.1234567890123456789',output_groups:[g('0.1234567890123456789')]});
 assert.equal(JSON.parse(body).command,'record_manufactured_output');assert.match(body,/"good":0\.1234567890123456789/);
 assert.equal(JSON.parse(body).args.payload.output_groups[0].quantity,'0.1234567890123456789');
});
