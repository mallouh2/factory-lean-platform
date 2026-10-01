import test from "node:test";
import assert from "node:assert/strict";
import { productionProgress, entryQuantities } from "../src/utils/production-recording.mjs";
import { createRequire } from "node:module";
import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { build } from "esbuild";
import en from "../src/locales/en.json" with {type:"json"};
import ar from "../src/locales/ar.json" with {type:"json"};
const require=createRequire(import.meta.url);
const bundle=await build({entryPoints:["src/features/ProductionRecording.tsx"],bundle:true,platform:"node",format:"cjs",packages:"external",write:false,logLevel:"silent"});
const module={exports:{}};
new Function("require","module","exports",bundle.outputFiles[0].text)(require,module,module.exports);
const snapshot={user:{id:"actor"},factory:{id:"f",timezone:"UTC"},tables:{
 production_recording_units:[{unit_kind:"line",unit_id:"line",item_id:"item"}],
 production_technicians:[{id:"tech",display_name:"Technician A",user_id:"actor"}],
 production_orders:[{id:"item",request_id:"request",product_id:"product",unit:"meter",target_quantity:1000,produced_quantity:570,rejected_quantity:20,good_quantity:550,remaining_quantity:450}],
 production_requests:[{id:"request",code:"PO-42"}],products:[{id:"product",name:"Pipe",name_ar:"أنبوب"}],
 production_lines:[{id:"line",name:"Line 1",name_ar:"الخط ١"}],production_entries:[]}};
function render(lang="en",edit=true,configure=()=>{},selectedLot){
 const s=structuredClone(snapshot);configure(s);const before=structuredClone(s);
 const dictionary=lang==="ar"?ar:en;
 const html=renderToStaticMarkup(createElement(module.exports.default,{snapshot:s,lang,t:k=>dictionary[k]||k,can:(_,action)=>action==="edit"?edit:true,selectedLot,command:()=>{throw Error("render must not write");}}));
 assert.deepEqual(s,before);return html;
}
test("good output and scrap remain separate across shifts",()=>{
 const progress=productionProgress(snapshot.tables.production_orders[0]);
 assert.equal(progress.good,550);assert.equal(progress.remaining,450);assert.equal(progress.percent,55);assert.equal(progress.scrap,20);
 assert.equal(productionProgress(snapshot.tables.production_orders[0],100).afterRemaining,350);
});
test("legacy gross/rejected semantics do not count scrap toward demand",()=>{
 assert.equal(productionProgress({target_quantity:1000,produced_quantity:570,rejected_quantity:20}).good,550);
 assert.deepEqual(entryQuantities({produced:120,rejected:20}),{good:100,scrap:20});
});
test("overproduction preserves output while remaining clamps to zero",()=>{
 const p=productionProgress({target_quantity:100,produced_quantity:125,rejected_quantity:5});
 assert.equal(p.good,120);assert.equal(p.remaining,0);assert.equal(p.overproduction,20);assert.equal(p.percent,120);
});
test("corrected values are displayed without losing original quantities",()=>{
 const entry={produced:120,rejected:20,good_quantity:100,scrap_quantity:20,effective_good:90,effective_scrap:25};
 const before=structuredClone(entry);assert.deepEqual(entryQuantities(entry),{good:90,scrap:25});assert.deepEqual(entry,before);
});
test("entry form and server-selected job render in EN/AR",()=>{
 for(const [lang,words] of [["en",en],["ar",ar]]){
  const html=render(lang);for(const key of ["productionRecording","recordingUnit","recordingTechnician","recordingGood","recordingScrap","recordingRequired","recordingGoodSoFar","recordingRemaining","recordingSubmit"])assert.ok(html.includes(words[key]),key);
  assert.ok(html.includes("PO-42"));assert.ok(html.includes("Technician A"));assert.match(html,/step="any"/);assert.doesNotMatch(html,/type="datetime-local"/);
 }
});
test("read-only person sees records without recording or correcting actions",()=>{
 const html=render("en",false);assert.ok(!html.includes(en.recordingSubmit));assert.ok(!html.includes(en.recordingCorrect));
});
test("no authoritative active unit blocks recording with actionable guidance",()=>{
 const html=render("en",true,s=>{s.tables.production_recording_units=[];});assert.ok(html.includes(en.recordingNoActive));assert.match(html,/<button class="primary" disabled/);
});
test("only supplied authoritative units enter selector; no normal-machine fallback",()=>{
 const html=render("en",true,s=>{s.tables.work_centers=[{id:"wrong",name:"Normal extruder",line_id:"line",order_id:"item"}];});
 assert.ok(!html.includes("Normal extruder"));assert.match(html,/value="line:line"/);
});
test("eligible independent machine uses its own unit without a fake line",()=>{
 const html=render("en",true,s=>{s.tables.production_recording_units=[{unit_kind:"machine",unit_id:"standalone",item_id:"item"}];s.tables.work_centers=[{id:"standalone",name:"Independent Printer",line_id:null}];});
 assert.ok(html.includes("Independent Printer"));assert.match(html,/value="machine:standalone"/);
});
test("history uses its own query rather than rendering capped snapshot entries",()=>{
 const html=render("en",true,s=>{s.tables.production_entries=[{id:"entry",order_id:"item",line_id:"line",technician_id:"tech",created_at:"2026-09-30T10:00:00Z",good_quantity:300,scrap_quantity:10,effective_good:300,effective_scrap:10,running_good:300,remaining_quantity:700}];});
  assert.ok(html.includes(en.productionHistory));assert.ok(html.includes(en.historyFilters));assert.ok(!html.includes(en.recordingCorrect));
});
test('server-detected shift renders without a required shift selector and excludes archived shifts',()=>{
 const html=render('en',true,s=>{s.tables.production_shifts=[{id:'day',name:'QA Day',name_ar:'نهار',archived:false,start_time:'06:00:00',end_time:'14:00:00'},{id:'old',name:'Archived shift',archived:true}];s.tables.production_shift_context=[{shift_id:'day',timezone:'Asia/Qatar',local_time:'07:30'}];});
 assert.match(html,/QA Day/);assert.doesNotMatch(html,/Archived shift/);assert.ok(html.includes(en.shiftAutoDetected));assert.match(html,/06:00–14:00/);
 assert.doesNotMatch(html,/<option value="day"/);
});
test('no configured shift permits transitional recording with setup guidance',()=>{
 assert.ok(render().includes(en.shiftSetup));
});
test('unfinished input renders original product/item, stock and only authoritative WIP destinations in EN/AR',()=>{
 const lot={id:'lot',factory_id:'f',item_id:'item',product_name:'Pipe',product_name_ar:'أنبوب',unit:'meter',quantity_available:380,request_code:'PO-42',remaining_work:'Printing',destinations:[{unit_kind:'machine',unit_id:'printer',item_id:'item'}]};
 for(const lang of ['en','ar']){const words=lang==='ar'?ar:en,html=render(lang,true,s=>{s.tables.work_centers=[{id:'printer',name:'Printer',name_ar:'طابعة'}];},lot);
  for(const key of ['unfinishedQuantity','unfinishedInputSource','unfinishedProduct','unfinishedAvailable','unfinishedProcess','unfinishedConservationHelp'])assert.ok(html.includes(words[key]));
  assert.match(html,/380/);assert.match(html,/Printing/);assert.match(html,/value="machine:printer"/);assert.doesNotMatch(html,/value="line:line"/);
 }
});
test('selected WIP from another factory is masked and cannot supply a production unit',()=>{
 const html=render('en',true,()=>{},{id:'foreign-lot',factory_id:'other',product_name:'Foreign private product',quantity_available:380,destinations:[{unit_kind:'machine',unit_id:'foreign-machine',item_id:'item'}]});
 assert.ok(!html.includes('Foreign private product'));assert.ok(!html.includes('machine:foreign-machine'));assert.match(html,/<button class="primary" disabled/);
});
