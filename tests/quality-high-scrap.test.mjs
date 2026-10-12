import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {qualityScrapState} from '../src/utils/quality-ui.mjs';
import {producedWeight} from '../src/utils/lean-analysis.mjs';
const input=(values={})=>({version:1,product_id:'P',line_id:'L1',unit:'meter',production_scrap_kg:'2',quality_scrap_kg:'0',produced_kg:'100',weight_kg_per_unit:'.5',running_standard_percent:'2',standard_revision:1,
 startup_id:null,startup_context_complete:true,startup_allowance_kg:'0',above_running_standard:false,running_excess_kg:'0',...values});
test('Below/equal/above and zero use the exact protected SQL boundary',()=>{
 for(const kg of ['0','1','2'])assert.equal(qualityScrapState(input({production_scrap_kg:kg})).status,'NORMAL');
 const high=qualityScrapState(input({production_scrap_kg:'2.01',above_running_standard:true,running_excess_kg:'.01'}));
 assert.equal(high.status,'HIGH');assert.equal(high.rate,2.01);assert.equal(high.excessKg,.01);
 assert.equal(qualityScrapState(input({running_standard_percent:'0',production_scrap_kg:'0'})).status,'NORMAL');
 assert.equal(qualityScrapState(input({production_scrap_kg:'.009',produced_kg:'.3',running_standard_percent:'3'})).high,false);
});
test('Historical snapshots and same Product on different Lines stay independent',()=>{
 const a=qualityScrapState(input({line_id:'L1',running_standard_percent:2,standard_revision:1,production_scrap_kg:3,above_running_standard:true,running_excess_kg:1,current_standard_percent:10}));
 const b=qualityScrapState(input({line_id:'L2',running_standard_percent:4,standard_revision:3,production_scrap_kg:3}));
 assert.equal(a.high,true);assert.equal(a.standard,2);assert.equal(b.high,false);assert.equal(b.standard,4);
 assert.equal(qualityScrapState([input(),input({product_id:'Other',line_id:'L2'})]).status,'MISSING_DATA');
});
test('Missing standard and missing mass never become healthy or zero',()=>{
 assert.equal(qualityScrapState(input({running_standard_percent:null,standard_revision:null})).status,'MISSING_STANDARD');
 for(const field of ['produced_kg','production_scrap_kg','quality_scrap_kg'])for(const value of [null,undefined,'',' ',true,-1,'bad',Infinity]){
  const result=qualityScrapState(input({[field]:value}));assert.equal(result.status,'MISSING_DATA');assert.equal(result.high,false);assert.equal(result.rate,null);
 }
 assert.equal(qualityScrapState(input({produced_kg:0})).status,'MISSING_DATA');
 assert.equal(qualityScrapState(undefined).status,'MISSING_DATA');
});
test('Actual KG percentage remains independent of missing standard, Line and startup context',()=>{
 const missing=qualityScrapState(input({running_standard_percent:null,standard_revision:null,startup_context_complete:false}));
 assert.equal(missing.rate,2);assert.equal(missing.status,'MISSING_STANDARD');assert.equal(missing.high,false);
 const context=qualityScrapState(input({line_id:null,startup_context_complete:false}));
 assert.equal(context.rate,2);assert.equal(context.status,'MISSING_DATA');
 assert.equal(qualityScrapState(input({weight_kg_per_unit:null})).rate,2,'captured gross KG remains authoritative without a separate weight field');
 assert.equal(qualityScrapState(input({produced_kg:null,current_product_weight:99})).rate,null);
 assert.equal(qualityScrapState(input({produced_kg:1e-300,production_scrap_kg:1e300})).rate,null);
});
test('A Startup reason alone excludes no Scrap; incomplete event association preserves the actual rate',()=>{
 const reason=qualityScrapState(input({reason:'Startup',startup_kg:3,production_scrap_kg:3,above_running_standard:true,running_excess_kg:1}));
 assert.equal(reason.rate,3);assert.equal(reason.startupAllowanceKg,0);assert.equal(reason.high,true);
 const broken=qualityScrapState(input({startup_id:'missing',startup_context_complete:false,startup_standard_kg:10,startup_standard_revision:1,startup_kg:2,previous_startup_kg:0,cumulative_startup_kg:2}));
 assert.equal(broken.rate,2);assert.equal(broken.status,'MISSING_DATA');assert.equal(broken.adjustedRate,null);assert.equal(broken.high,false);
});
test('Meter/Piece KG use captured Good + newly recorded WIP mass, not accepted Good',()=>{
 for(const unit of ['meter','piece']){
  const kg=producedWeight({good:100,newly_recorded_wip:20,unit,weight_unit:unit,kg_per_unit:2});
  const result=qualityScrapState(input({unit,produced_kg:kg,weight_kg_per_unit:2,production_scrap_kg:10,accepted_good:40,running_standard_percent:5}));
  assert.equal(kg,240);assert.equal(result.rate,1000/240);
 }
});
test('Recorded startup allowance is shared across shifts and excess event remains abnormal',()=>{
 const startup={startup_id:'S',startup_standard_kg:10,startup_standard_revision:2};
 const first=qualityScrapState(input({...startup,startup_kg:6,previous_startup_kg:0,cumulative_startup_kg:6,production_scrap_kg:6,startup_allowance_kg:6,shift_id:'A'}));
 const second=qualityScrapState(input({...startup,startup_kg:4,previous_startup_kg:6,cumulative_startup_kg:10,production_scrap_kg:6,startup_allowance_kg:4,shift_id:'B'}));
 assert.equal(first.high,false);assert.equal(first.rate,6);assert.equal(first.adjustedRate,0);assert.equal(second.high,false);assert.equal(second.adjustedRate,2);
 const third=qualityScrapState(input({...startup,startup_kg:1,previous_startup_kg:10,cumulative_startup_kg:11,production_scrap_kg:1,startup_allowance_kg:0}));
 assert.equal(third.high,true);assert.equal(third.startupExcessKg,1);assert.equal(third.excessKg,0);
 assert.equal(qualityScrapState(input({shift_id:'A',startup_standard_kg:100,production_scrap_kg:3,above_running_standard:true,running_excess_kg:1})).high,true);
 assert.equal(qualityScrapState(input({...startup,startup_context_complete:false})).status,'MISSING_DATA');
 assert.equal(qualityScrapState(input({...startup,startup_kg:0,previous_startup_kg:0,cumulative_startup_kg:0,startup_standard_kg:null})).status,'MISSING_STANDARD');
});
test('Separate permanent KG sums once; rework snapshots and recoverable WIP are not extra Scrap',()=>{
 const result=qualityScrapState(input({production_scrap_kg:2,quality_scrap_kg:1,above_running_standard:true,running_excess_kg:1,rework_quantity:80,quality_rework_records:[{actual_scrap_kg:2}],current_product_weight:99}));
 assert.equal(result.rate,3);assert.equal(result.excessKg,1);
});
test('Whole-row warning styling follows zebra and protects hover/focus/selection',()=>{
 const css=readFileSync('src/app/globals.css','utf8'),warning=css.indexOf('tr:is(.high-scrap');
 assert.ok(warning>css.indexOf('--table-row-alternate:'));
 assert.match(css.slice(warning),/--table-row-bg: color-mix/);
 assert.match(css.slice(warning),/:hover,:focus-within,\[aria-selected="true"\]/);
 assert.match(css.slice(warning),/outline: 2px solid var\(--primary\)/);
});
