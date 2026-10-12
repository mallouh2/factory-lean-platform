import test from 'node:test';
import assert from 'node:assert/strict';
import {decimalCompare,decimalMultiply,decimalSubtract,quantityValid,scrapWeight} from '../src/utils/quality-quantities.mjs';
import {qualityCommandValid,sourceCommandValid,qualityRequiredPermissions,sourceRequiredPermissions} from '../src/utils/quality-contract.mjs';
import {productionProgress} from '../src/utils/production-recording.mjs';
const id='12345678-1234-1234-1234-123456789abc';
test('Scrap defaults preserve exact meter and piece mass without binary rounding',()=>{
 assert.equal(scrapWeight('20','meter','.35','7').defaultKg,'7');
 assert.equal(scrapWeight('10','piece','.25','2.7').defaultKg,'2.5');
 assert.equal(scrapWeight('10','piece','.25','2.7').overridden,true);
 assert.equal(decimalMultiply('.1','.2'),'0.02');
 assert.equal(decimalMultiply('1.125','.35'),'0.39375');
});
test('Exact decimal quantities include exponent notation and values beyond JS safe integers',()=>{
 assert.equal(decimalSubtract('9007199254740993','9007199254740992'),'1');
 assert.equal(decimalCompare('1e-7','0.0000001'),0);
 assert.equal(decimalMultiply('9007199254740993','.1'),'900719925474099.3');
 assert.equal(decimalSubtract('10','.75'),'9.25');
});
test('Pieces require integers; missing weight needs positive manual kg; invalid and nonfinite input rejected',()=>{
 for(const value of ['NaN','Infinity','-Infinity','','-1','0','1e1001'])assert.equal(quantityValid(value,'meter'),false,value);
 assert.equal(quantityValid('0.5','piece'),false);assert.equal(quantityValid('10e-1','piece'),true);
 assert.equal(quantityValid('1.125','meter','1.12'),false);assert.equal(quantityValid('1.125','meter','1.125'),true);
 assert.equal(scrapWeight('10','piece',null,'').valid,false);
 assert.deepEqual(scrapWeight('10','piece',null,'2.75'),{defaultKg:null,actualKg:'2.75',valid:true,overridden:true});
});
test('Quality and source API contracts reject forged fields and enforce bounded source picks',()=>{
 const command={factory:id,request_id:id,operation:'reject',payload:{source:id,quantity:'2',reason:id,disposition:'SCRAP',actual_scrap_kg:'.7',physically_identified:true}};
 assert.equal(qualityCommandValid(command),true);
 assert.equal(qualityCommandValid({...command,payload:{...command.payload,created_by:id}}),false);
 assert.equal(qualityCommandValid({...command,factory:'other'}),false);
 const source={factory:id,request_id:id,operation:'adjust',payload:{product:id,unit:'meter',quantity:'-2',reason:'Physical count'},allocations:[{source_id:null,quantity:'2'}]};
 assert.equal(sourceCommandValid(source),true);
 assert.equal(sourceCommandValid({...source,allocations:[{source_id:id,quantity:2}]}),false);
 assert.equal(sourceCommandValid({...source,allocations:Array(101).fill(source.allocations[0])}),false);
 assert.equal(sourceCommandValid({...source,payload:{...source.payload,actor:id}}),false);
});
test('Quality permissions are per-person and independent from Warehouse and Production roles',()=>{
 assert.deepEqual(qualityRequiredPermissions('reject'),[['quality','view'],['quality','create']]);
 assert.deepEqual(qualityRequiredPermissions('reverse'),[['quality','view'],['quality','edit']]);
 assert.deepEqual(qualityRequiredPermissions('replacement'),[['orders','view'],['orders','create']]);
 assert.deepEqual(sourceRequiredPermissions('correct'),[['orders','view'],['orders','edit']]);
 assert.deepEqual(sourceRequiredPermissions('dispatch'),[['warehouse','issue']]);
});
test('Production progress uses accepted and linked recovery totals while legacy values remain supported',()=>{
 const original={target_quantity:100,good_quantity:110,remaining_quantity:0,overproduction_quantity:10,fulfillment_good_quantity:90,accepted_remaining_quantity:10};
 assert.equal(productionProgress(original).good,90);assert.equal(productionProgress(original).remaining,10);assert.equal(productionProgress(original).overproduction,0);
 assert.equal(productionProgress(original,10).afterRemaining,0);assert.equal(original.good_quantity,110);
 assert.equal(productionProgress({target_quantity:100,good_quantity:80,remaining_quantity:20}).good,80);
});
