import test from 'node:test';
import assert from 'node:assert/strict';
import { qualityScrapState as assess } from '../src/utils/quality-ui.mjs';
// Exercise the additive protected-reader contract, including SQL's exact boundary.
const qualityScrapState=(scrap,mass,standard)=>assess({version:1,product_id:'P',line_id:'L',unit:'piece',weight_kg_per_unit:2,
 production_scrap_kg:scrap,quality_scrap_kg:0,produced_kg:mass,running_standard_percent:standard,standard_revision:1,
 startup_context_complete:true,startup_allowance_kg:0,above_running_standard:Number(scrap)*100>Number(mass)*Number(standard),
 running_excess_kg:Math.max(0,Number(scrap)-Number(mass)*Number(standard)/100)});

test('Quality visual ratio uses kg mass, with strict approved threshold boundary',()=>{
 // 100 Good + 20 newly recorded WIP at 2 kg/unit = 240 kg, not 120 production units.
 assert.equal(qualityScrapState(10,240,5).high,false);
 assert.equal(qualityScrapState(12,240,5).rate,5);
 assert.equal(qualityScrapState(12,240,5).high,false);
 assert.equal(qualityScrapState(12.01,240,5).high,true);
 assert.equal(qualityScrapState(0,240,0).high,false);
 assert.equal(qualityScrapState(1,240,0).high,true);
});
test('Unavailable mass/Scrap never becomes zero and no threshold is invented',()=>{
 for(const mass of [null,undefined,'',0,'bad',Infinity])assert.equal(qualityScrapState(10,mass,5).rate,null);
 for(const scrap of [null,undefined,'',' ',true,-1,'bad',Infinity])assert.equal(qualityScrapState(scrap,240,5).rate,null);
 for(const threshold of [null,undefined,'',-1,'bad',Infinity])assert.equal(qualityScrapState(12.01,240,threshold).high,false);
 assert.equal(qualityScrapState(0,240,null).rate,0);
});
