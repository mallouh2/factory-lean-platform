import test from 'node:test';
import assert from 'node:assert/strict';
import {requestCreators,requestPresentation,requestQueueMatches,requestStatusMatches} from '../src/utils/request-queue.mjs';
const request={code:'PO-47',name:'Pipe project'};
const items=[{product_id:'P',line_id:'L',target_quantity:40,start_time:'2026-10-01T07:00:00Z'}];
const products=[{id:'P',name:'PVC pipe',name_ar:'أنبوب بلاستيك',code:'PVC25'}];
test('request search matches request/product names and codes in EN/AR, with all typed terms required',()=>{
  for(const search of ['PO-47','pipe project','PVC25','أنبوب بلاستيك','po-47 pvc'])
    assert.equal(requestQueueMatches(request,items,products,{search}),true);
  assert.equal(requestQueueMatches(request,items,products,{search:'PO-47 missing'}),false);
});

test('request lifecycle colors derive from actual item states and preserve scheduled/overdue as separate signals',()=>{
  const now=Date.parse('2026-10-01T10:00:00Z');
  const planned={status:'planned',line_id:'L',start_time:'2026-10-02T10:00:00Z',expected_finish:'2026-10-02T11:00:00Z'};
  const before=JSON.stringify(planned);
  assert.equal(requestPresentation({},[],now).tone,'waiting');
  assert.equal(requestPresentation({},[{status:'planned'}],now).tone,'waiting');
  assert.equal(requestPresentation({},[planned],now).tone,'scheduled');
  const late=requestPresentation({required_by:'2026-10-01T09:00:00Z'},[planned],now);
  assert.equal(late.label,'requestScheduled');
  assert.equal(late.state,'scheduled');assert.equal(late.tone,'delayed');assert.equal(late.overdue,true);
  assert.equal(requestPresentation({},[{status:'active'}],now).tone,'active');
  assert.equal(requestPresentation({},[{status:'completed'},{status:'planned'}],now).status,'active');
  assert.equal(requestPresentation({},[{status:'completed'},{status:'planned'}],now).label,'active');
  assert.equal(requestPresentation({},[{status:'active'}],now).label,'executionInProduction');
  for(const status of ['completed','cancelled']){
    const done=requestPresentation({required_by:'2026-09-01'},[{status}],now);
    assert.equal(done.tone,status);assert.equal(done.overdue,false);
  }
  assert.equal(JSON.stringify(planned),before);
});

test('single and multiple status selections use OR across lifecycle; deadline-only overdue is discoverable',()=>{
  const now=Date.parse('2026-10-01T10:00:00Z');
  const request={required_by:'2026-09-01'},planned=[{status:'planned'}];
  for(const selected of [[],['all'],['planned'],['active','planned'],['delayed']])
    assert.equal(requestStatusMatches(request,planned,selected,now),true);
  assert.equal(requestStatusMatches(request,planned,['active','completed'],now),false);
  assert.equal(requestStatusMatches(request,[{status:'completed'}],['delayed'],now),false);
});

test('Requested By uses creator IDs including missing legacy identities, without merging people sharing a name',()=>{
  const rows=[{id:'A',requested_by:'U1',requested_by_name:'Ahmad'},
    {id:'B',requested_by:'U2',requested_by_name:'Ahmad'}, {id:'C',requested_by:null},
    {id:'D',requested_by:'U1',requested_by_name:'Ahmad'}];
  const before=JSON.stringify(rows);
  assert.equal(requestCreators(rows).length,3);
  assert.deepEqual(rows.filter(r=>requestQueueMatches(r,[],[],{creator:'U1'})).map(r=>r.id),['A','D']);
  assert.deepEqual(rows.filter(r=>requestQueueMatches(r,[],[],{creator:'unrecorded'})).map(r=>r.id),['C']);
  assert.equal(JSON.stringify(rows),before);
});

test('filters inspect every retained Product Item, including siblings beyond the two-item row preview',()=>{
  const allItems=[...items,{product_id:'P2',line_id:'L2'},{product_id:'P3',line_id:'L3'}];
  assert.equal(requestQueueMatches(request,allItems,products,{product:'P3',line:'L3'}),true);
});
test('product and planned-line filters use retained item facts and never mutate scheduling data',()=>{
  const before=JSON.stringify({request,items,products});
  assert.equal(requestQueueMatches(request,items,products,{product:'P',line:'L'}),true);
  assert.equal(requestQueueMatches(request,items,products,{line:'X'}),false);
  assert.equal(requestQueueMatches(request,items,products,{product:'X'}),false);
  assert.equal(requestQueueMatches(request,items,products,{}),true);
  assert.equal(JSON.stringify({request,items,products}),before);
});
