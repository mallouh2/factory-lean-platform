import test from 'node:test';
import assert from 'node:assert/strict';
import {defaultHistoryColumns,historyColumns,historyNumber,historyPreferenceKey,historyScrapRate,productionDates,visibleHistoryColumns} from '../src/utils/production-history-view.mjs';
test('approved seven columns have fixed order and never include status or actions',()=>{
 assert.deepEqual(defaultHistoryColumns,['date','shift','line','order','product','good','scrap']);
 assert.ok(!historyColumns.some(([key])=>['actions','corrected','status'].includes(key)));
});
test('preferences ignore removed, unknown and unauthorized columns; empty layout restores a usable default',()=>{
 assert.deepEqual(visibleHistoryColumns(['machine','removed','good'],['good','date']),['good']);
 assert.deepEqual(visibleHistoryColumns([]),defaultHistoryColumns);assert.deepEqual(visibleHistoryColumns('broken'),defaultHistoryColumns);
 assert.deepEqual(visibleHistoryColumns(['scrap','good','scrap']),['good','scrap']);
});
test('preferences are individually scoped by actor, factory and table and store identifiers only',()=>{
 const key=historyPreferenceKey('owner','factoryA');assert.notEqual(key,historyPreferenceKey('other','factoryA'));assert.notEqual(key,historyPreferenceKey('owner','factoryB'));
 assert.ok(key.includes('production-history'));assert.equal(historyPreferenceKey(null,'factory'),null);
});
test('attribution dates never substitute late submission time',()=>{
 assert.deepEqual(productionDates({created_at:'2026-10-21T07:00:00Z'},'UTC'),[]);
 assert.deepEqual(productionDates({effective_occurrence:{business_date:'2026-10-19'},created_at:'2026-10-21T07:00:00Z'},'UTC'),['2026-10-19']);
 assert.deepEqual(productionDates({effective_period_start:'2026-10-19T21:30:00Z',effective_period_end:'2026-10-20T00:30:00Z'},'UTC'),['2026-10-19','2026-10-20']);
 assert.deepEqual(productionDates({effective_period_start:'bad',effective_period_end:'bad'},'UTC'),[]);
});
for(const basis of ['RECORDING_CONFIG','VERIFIED_HISTORICAL'])test('Scrap rate reuses KG output evidence: '+basis,()=>{
 assert.equal(historyScrapRate({effective_scrap_kg:'10',produced_weight_kg:'240',weight_basis:basis}),100*10/240);
});
for(const row of [{effective_scrap_kg:'10',effective_good:'500',unit:'meter'},{effective_scrap_kg:'10',produced_weight_kg:'240',weight_basis:'UNKNOWN'},{effective_scrap_kg:null,produced_weight_kg:'240',weight_basis:'RECORDING_CONFIG'},{effective_scrap_kg:'1',produced_weight_kg:'0',weight_basis:'RECORDING_CONFIG'}])test('missing or incompatible weight evidence has no invented percentage '+JSON.stringify(row),()=>assert.equal(historyScrapRate(row),null));
test('exact values and missing values stay distinguishable in EN/AR',()=>{
 assert.equal(historyNumber(null),null);assert.equal(historyNumber('0'),'0');assert.equal(historyNumber('9007199254740993.123456789'),'9,007,199,254,740,993.123456789');
 assert.equal(historyNumber('-0.25'),'-0.25');assert.ok(historyNumber('12.25','ar').includes(new Intl.NumberFormat('ar',{useGrouping:false}).format(25)));
});
