import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
const require=createRequire(import.meta.url);
const bundle=await build({entryPoints:['src/components/useNavigationOverlay.ts'],bundle:true,
  platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'});
function run(mobile, check) {
  const original={document:globalThis.document,window:globalThis.window,setTimeout,clearTimeout};
  const listeners={},effects=[],timers=[];let focused=null;const collapsed=[],mobileChanges=[];
  const first={getClientRects:()=>[1],focus:()=>{focused=first;}},last={getClientRects:()=>[1],focus:()=>{focused=last;}};
  const inside={};
  globalThis.document={activeElement:inside,addEventListener:(event,fn)=>{listeners[event]=fn;},removeEventListener:()=>{}};
  globalThis.window={matchMedia:()=>({matches:!mobile})};
  globalThis.setTimeout=(fn,ms)=>{assert.equal(ms,150);timers.push(fn);return timers.length;};
  globalThis.clearTimeout=()=>{timers.length=0;};
  const module={exports:{}};
  try {
    new Function('require','module','exports',bundle.outputFiles[0].text)(name=>name==='react'?{
      useRef:value=>({current:value}),useEffect:fn=>effects.push(fn)}:require(name),module,module.exports);
    const hook=module.exports.useNavigationOverlay(mobile,value=>mobileChanges.push(value),value=>collapsed.push(value));
    hook.sidebarRef.current={contains:element=>element===inside,querySelector:()=>first,querySelectorAll:()=>[first,last]};
    const cleanup=effects.map(fn=>fn());
    check({hook,listeners,timers,collapsed,mobileChanges,first,last,inside,focused:()=>focused});
    cleanup.forEach(fn=>fn?.());
  } finally {Object.assign(globalThis,original);}
}
test('mouse overlay expands and collapses after leave even when a clicked item retains focus',()=>run(false,({hook,timers,collapsed})=>{
  hook.onPointerEnter({pointerType:'mouse'});assert.deepEqual(collapsed,[false]);
  hook.onPointerLeave();timers.at(-1)();assert.deepEqual(collapsed,[false,true]);
}));
test('keyboard focus keeps desktop overlay open until focus leaves; touch cannot hover-expand',()=>run(false,({hook,listeners,timers,collapsed})=>{
  hook.onPointerEnter({pointerType:'touch'});assert.deepEqual(collapsed,[]);
  listeners.keydown({key:'Tab'});hook.onFocusCapture();hook.onPointerLeave();timers.at(-1)();
  assert.deepEqual(collapsed,[false]);document.activeElement=null;hook.onBlurCapture();timers.at(-1)();
  assert.deepEqual(collapsed,[false,true]);
}));
test('mobile opening focuses close, traps Tab in both directions, and Escape closes',()=>run(true,({hook,first,last,focused,mobileChanges})=>{
  assert.equal(focused(),first);
  let prevented=0;document.activeElement=last;
  hook.onKeyDown({key:'Tab',preventDefault:()=>prevented++});assert.equal(focused(),first);
  document.activeElement=first;hook.onKeyDown({key:'Tab',shiftKey:true,preventDefault:()=>prevented++});
  assert.equal(focused(),last);assert.equal(prevented,2);
  hook.onKeyDown({key:'Escape',preventDefault:()=>{},stopPropagation:()=>{}});assert.deepEqual(mobileChanges,[false]);
}));
