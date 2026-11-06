import test from 'node:test';
import assert from 'node:assert/strict';
import {historyFetch} from '../src/utils/production-history.mjs';
const raw='{"total":1,"page":1,"page_size":50,"rows":[{"id":"row","effective_good":0.1234567890123456789,"running_good":45.1234567890123456789,"remaining_quantity":54.8765432109876543211,"correction_count":0}]}';
test('legacy History and shared export transport retain exact quantities and integer page controls',async()=>{
 const response=await historyFetch(async()=>new Response(raw))('http://127.0.0.1:4291/rest/v1/rpc/production_history',{method:'POST'}),data=await response.json();
 assert.equal(data.rows[0].effective_good,'0.1234567890123456789');assert.equal(data.rows[0].running_good,'45.1234567890123456789');assert.equal(data.rows[0].remaining_quantity,'54.8765432109876543211');assert.equal(data.rows[0].correction_count,0);assert.equal(data.total,1);assert.equal(data.page_size,50);
});
test('supplementary Scrap KG, output weight and genuine zero retain precision',async()=>{
 const response=await historyFetch(async()=>new Response('[{"effective_scrap_kg":0.01234567890123456789,"produced_weight_kg":0.06172839450617283945,"effective_startup_kg":0}]'))('http://127.0.0.1:4291/rest/v1/production_entries');
 const [row]=await response.json();assert.equal(row.effective_scrap_kg,'0.01234567890123456789');assert.equal(row.produced_weight_kg,'0.06172839450617283945');assert.equal(row.effective_startup_kg,'0');
});
test('unrelated responses and authorization failures are returned untouched',async()=>{
 for(const [endpoint,status]of [['can_access',200],['production_history',403]]){const response=new Response('{"allowed":true,"number":1.25}',{status}),result=await historyFetch(async()=>response)('http://127.0.0.1:4291/rest/v1/rpc/'+endpoint);assert.equal(result,response);}
});
test('unsafe integer controls fail closed instead of rounding',async()=>{
 await assert.rejects(()=>historyFetch(async()=>new Response('{"total":9007199254740993}'))('http://127.0.0.1:4291/rest/v1/rpc/production_history'),/history_invalid/);
});
