import test from 'node:test';
import assert from 'node:assert/strict';
import {detailsRowHandlers} from '../src/utils/table-details.mjs';

function fixture(disabled=false){
 const calls=[],pointer={current:''},row={},target={closest:()=>null};
 const event={target,currentTarget:row,defaultPrevented:false,preventDefault(){this.defaultPrevented=true;}};
 return {calls,event,handlers:detailsRowHandlers(pointer,()=>calls.push('select'),()=>calls.push('details'),disabled)};
}
test('single click selects only; double click selects and opens Details',()=>{
 const {handlers,event,calls}=fixture();handlers.onPointerDown({pointerType:'mouse'});handlers.onClick(event);assert.deepEqual(calls,['select']);
 handlers.onDoubleClick(event);assert.deepEqual(calls,['select','select','details']);
});
for(const name of ['button','link','checkbox','input','select','textarea','contenteditable','label'])test(name+' nested controls never trigger row selection or Details',()=>{
 const {handlers,event,calls}=fixture();event.target.closest=()=>({control:name});handlers.onClick(event);handlers.onDoubleClick(event);handlers.onKeyDown({...event,key:'Enter'});assert.deepEqual(calls,[]);
});
test('touch selection remains normal and double tap does not open Details',()=>{
 const {handlers,event,calls}=fixture();handlers.onPointerDown({pointerType:'touch'});handlers.onClick(event);handlers.onDoubleClick(event);assert.deepEqual(calls,['select']);
 handlers.onPointerDown({pointerType:'mouse'});handlers.onDoubleClick(event);assert.deepEqual(calls,['select','select','details']);
});
test('Enter opens Details, Space selects; nested and disabled actions stay inert',()=>{
 const {handlers,event,calls}=fixture();event.target=event.currentTarget;handlers.onKeyDown({...event,key:'Enter'});handlers.onKeyDown({...event,key:' '});assert.deepEqual(calls,['select','details','select']);
 const blocked=fixture(true);blocked.handlers.onDoubleClick(blocked.event);blocked.handlers.onClick(blocked.event);assert.deepEqual(blocked.calls,[]);
});
test('already-handled events and other keys do nothing',()=>{
 const {handlers,event,calls}=fixture();handlers.onDoubleClick({...event,defaultPrevented:true});handlers.onKeyDown({...event,key:'Delete'});assert.deepEqual(calls,[]);
});
