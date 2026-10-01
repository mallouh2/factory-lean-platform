import test from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import {createElement} from 'react';
import {renderToStaticMarkup} from 'react-dom/server';
import {shiftWindow} from '../src/utils/production-shifts.mjs';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};
const require=createRequire(import.meta.url);
async function component(path){const result=await build({entryPoints:[path],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'});const module={exports:{}};new Function('require','module','exports',result.outputFiles[0].text)(require,module,module.exports);return module.exports.default;}
const Shifts=await component('src/features/ProductionShifts.tsx'),Recording=await component('src/features/ProductionRecording.tsx');
const night={id:'night',name:'Night',name_ar:'ليل',archived:false,start_time:'22:00:00',end_time:'06:00:00'};
function render(Component,lang='en',context={shift_id:'night',timezone:'America/New_York',local_time:'02:00'},edit=true,shifts=[night]){
 const s={user:{id:'u'},factory:{id:'f',timezone:'America/New_York'},tables:{production_shifts:shifts,production_shift_context:context?[context]:[],production_technicians:[],production_recording_units:[]}};
 const before=structuredClone(s),dictionary=lang==='ar'?ar:en;
 const html=renderToStaticMarkup(createElement(Component,{snapshot:s,lang,t:k=>dictionary[k]||k,can:(_,a)=>a==='edit'?edit:true,command:()=>{throw Error('Rendering cannot write');}}));assert.deepEqual(s,before);return html;
}
test('time-window display preserves overnight meaning without converting through browser timezone',()=>{assert.deepEqual(shiftWindow(night),{start:'22:00',end:'06:00',overnight:true});assert.equal(shiftWindow({}),null);assert.equal(shiftWindow({...night,start_time:'06:00',end_time:'14:00'}).overnight,false);});
test('display does not hide second precision or mislabel an almost-full-day overnight window',()=>{assert.deepEqual(shiftWindow({start_time:'22:00:30',end_time:'22:00:10'}),{start:'22:00:30',end:'22:00:10',overnight:true});});
test('management shows factory timezone, window and overnight in EN/AR',()=>{for(const lang of ['en','ar']){const html=render(Shifts,lang),words=lang==='ar'?ar:en;assert.ok(html.includes(words.shiftOvernight));assert.match(html,/22:00.*06:00/);assert.match(html,/America\/New_York/);assert.match(html,/dir="ltr"/);if(lang==='ar')assert.match(html,/dir="rtl"/);}});
test('legacy untimed configuration is explicitly flagged rather than given invented times',()=>{assert.ok(render(Shifts,'en',{},true,[{id:'old',name:'Old shift',name_ar:'قديمة'}]).includes(en.shiftSetTimes));});
test('per-person read permission does not expose configuration actions',()=>{assert.ok(!render(Shifts,'en',{},false).includes(en.shiftCreate));assert.ok(!render(Shifts,'en',{},false).includes(en.edit));});
test('recording uses supplied server identity even when displayed factory time could belong to a different window',()=>{const html=render(Recording,'en',{shift_id:'night',timezone:'America/New_York',local_time:'07:30'});assert.ok(html.includes('Night'));assert.ok(html.includes(en.shiftAutoDetected));assert.ok(html.includes('07:30'));});
test('server no-match is explicit and never fabricates an automatic shift',()=>{for(const lang of ['en','ar']){const html=render(Recording,lang,{shift_id:null,timezone:'UTC',local_time:'12:00'}),words=lang==='ar'?ar:en;assert.ok(html.includes(words.shiftNoMatch));assert.ok(html.includes(words.shiftManualChoose));assert.ok(!html.includes(words.shiftAutoDetected));}});
test('missing server context shows loading rather than claiming no match',()=>{const html=render(Recording,'en',null);assert.ok(html.includes(en.loading));assert.ok(!html.includes(en.shiftNoMatch));});
test('no active configuration preserves transitional setup guidance and avoids manual picker',()=>{const html=render(Recording,'en',{shift_id:null},true,[]);assert.ok(html.includes(en.shiftSetup));assert.ok(!html.includes(en.shiftManualChoose));});
test('read-only recorder has no manual override controls',()=>{assert.ok(!render(Recording,'en',{},false).includes(en.shiftManualChoose));});
test('window, override and overlap errors have translated EN/AR guidance',()=>{for(const key of ['shiftStart','shiftEnd','shiftWindowInvalid','shiftOverlap','shiftNoMatch','shiftOverrideReason','shiftOverrideReasonRequired']){assert.ok(en[key]);assert.ok(ar[key]);assert.notEqual(en[key],ar[key]);}});
