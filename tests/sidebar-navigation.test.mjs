import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {build} from 'esbuild';
import {operationalNavigation,navigationLabel} from '../src/utils/operational-navigation.mjs';
import {permissionModule} from '../src/utils/permission-preview.mjs';
import en from '../src/locales/en.json' with {type:'json'};
import ar from '../src/locales/ar.json' with {type:'json'};

const require=createRequire(import.meta.url),react=require('react');
const bundle=await build({entryPoints:['src/components/OperationalNavigation.tsx'],bundle:true,platform:'node',format:'cjs',packages:'external',write:false,logLevel:'silent'});
function harness(grants=null,lang='en',active='floor',expanded=true) {
  const can=(module,action='view')=>grants===null||grants.includes(permissionModule(module)+(action==='view'?'':':'+action)),words=lang==='ar'?ar:en;
  let open,actions=[],effects=[];
  const module={exports:{}};
  new Function('require','module','exports',bundle.outputFiles[0].text)(name=>name==='react'?{...react,
    useState:initial=>{open??=initial;return[open,value=>{open=typeof value==='function'?value(open):value;}];},
    useEffect:fn=>effects.push(fn)}:require(name),module,module.exports);
  const render=()=>module.exports.default({can,t:key=>words[key]||key,active,expanded,onExpand:()=>{expanded=true;},onNavigate:id=>actions.push(id)});
  return{render,actions,effects};
}
const walk=node=>!node||typeof node!=='object'?[]:Array.isArray(node)?node.flatMap(walk):[node,...walk(node.props?.children)];

for(const lang of ['en','ar'])test(`direct destinations need one click and no disclosure: ${lang}`,()=>{
  const h=harness(null,lang),nodes=walk(h.render());
  for(const id of ['sales','planning','quality','maintenance','lean']) {
    const buttons=nodes.filter(n=>n.type==='button'&&n.props['data-destination']===id);
    assert.equal(buttons.length,1,id);assert.equal(buttons[0].props['aria-expanded'],undefined);
    buttons[0].props.onClick();assert.equal(h.actions.at(-1),id);
  }
  assert.ok(!nodes.some(n=>n.props?.['data-destination']==='lines'));
  assert.ok(!nodes.some(n=>n.props?.['data-destination']==='reports'));
  assert.ok(!nodes.some(n=>n.props?.['data-destination']==='downtime'));
});

test('permission filtering occurs before single-child flattening',()=>{
  for(const [grant,destinations]of[['lines',['floor']],['employees',['employees']],['suppliers',['suppliers']]]) {
    const h=harness([permissionModule(grant)]),nodes=walk(h.render());
    assert.deepEqual(nodes.filter(n=>n.props?.['data-destination']).map(n=>n.props['data-destination']),destinations);
    assert.equal(nodes.filter(n=>n.props?.['aria-expanded']!==undefined).length,0);
  }
});

test('Purchasing opens directly; distinct secondary destinations have a separate toggle',()=>{
  const h=harness(),nodes=walk(h.render()),group=nodes.find(n=>n.props?.['data-group']==='purchasing'),buttons=walk(group).filter(n=>n.type==='button');
  assert.equal(buttons.filter(n=>n.props['data-destination']==='purchasing').length,1);
  assert.equal(buttons.filter(n=>n.props['aria-expanded']!==undefined).length,1);
  assert.equal(buttons.find(n=>n.props['data-destination']==='suppliers')!==undefined,true);
  assert.equal(nodes.find(n=>n.props?.['data-destination']==='suppliers'),buttons.find(n=>n.props['data-destination']==='suppliers'));
});

test('Purchasing without secondary permissions is a direct destination',()=>{
  const h=harness(['purchasing']),nodes=walk(h.render());
  assert.equal(nodes.filter(n=>n.props?.['data-destination']==='purchasing').length,1);
  assert.equal(nodes.filter(n=>n.props?.['aria-expanded']!==undefined).length,0);
});

test('Warehouse keeps two distinct destinations and Administration retains authorized tools',()=>{
  const groups=operationalNavigation(()=>true);
  assert.deepEqual(groups.find(g=>g.id==='warehouse').items,['warehouse','warehouseRequests']);
  assert.deepEqual(groups.find(g=>g.id==='administration').items,['settings','employees','roles','audit','support']);
  assert.deepEqual(groups.find(g=>g.id==='production').items,['floor','orders','productionHistory','products','manageLinesMachines']);
});

test('all restricted permission combinations retain only allowed destinations',()=>{
  const modules=['sales','warehouse','purchasing','suppliers','myPurchaseRequests','lines','orders','planning','products','lean','downtime','quality','maintenance','settings','employees','roles','audit','support'];
  for(const module of modules) {
    const allowed=page=>permissionModule(page)===permissionModule(module),groups=operationalNavigation(allowed);
    for(const group of groups)for(const item of group.items) {
      const permission={floor:'lines',warehouseRequests:'warehouse',productionHistory:'orders',manageLinesMachines:'lines'}[item]||item;
      assert.equal(allowed(permission),true,item);
    }
  }
  assert.deepEqual(operationalNavigation(()=>false),[]);
});

test('downtime-only access keeps an authorized direct entry without granting Lean',()=>{
  const lean=operationalNavigation(page=>page==='downtime').find(group=>group.id==='lean');
  assert.deepEqual(lean.items,['downtime']);
  assert.equal(lean.label,'lean');
});

test('closed submenus are inert and toggles preserve active child semantics',()=>{
  const h=harness(),before=walk(h.render()),toggle=before.find(n=>n.props?.['aria-controls']==='navigation-warehouse');
  assert.equal(toggle.props['aria-expanded'],false);assert.equal(before.find(n=>n.props?.id==='navigation-warehouse').props.inert,true);
  toggle.props.onClick({stopPropagation(){}});const after=walk(h.render());
  assert.equal(after.find(n=>n.props?.['aria-controls']==='navigation-warehouse').props['aria-expanded'],true);
  assert.equal(after.find(n=>n.props?.id==='navigation-warehouse').props.inert,false);
  assert.equal(after.find(n=>n.props?.['data-destination']==='floor').props['aria-current'],'page');
});

test('navigation labels translate and never create duplicate destination names',()=>{
  for(const words of [en,ar]) {
    const labels=operationalNavigation(()=>true).flatMap(g=>g.items).map(item=>words[navigationLabel(item)]);
    assert.ok(labels.every(Boolean));assert.equal(new Set(labels).size,labels.length);
  }
});

test('collapsed rail reports hidden children accurately and opens the requested group in one action',()=>{
  const h=harness(null,'en','floor',false),before=walk(h.render());
  const toggle=before.find(n=>n.props?.['aria-controls']==='navigation-production');
  assert.equal(toggle.props['aria-expanded'],false);
  assert.equal(before.find(n=>n.props?.id==='navigation-production').props.inert,true);
  toggle.props.onClick({stopPropagation(){}});const after=walk(h.render());
  assert.equal(after.find(n=>n.props?.['aria-controls']==='navigation-production').props['aria-expanded'],true);
  assert.equal(after.find(n=>n.props?.id==='navigation-production').props.inert,false);
});

for(const lang of ['en','ar'])for(const expanded of [true,false])test('parent and chevron '+lang+expanded,()=>{for(const [id,dest]of [['production','floor'],['warehouse','warehouse']]){const h=harness(null,lang,'planning',expanded);let g=walk(h.render()).find(n=>n.props?.['data-group']===id);walk(g).find(n=>n.type==='button'&&n.props['aria-expanded']===undefined).props.onClick();assert.deepEqual(h.actions,[dest]);g=walk(h.render()).find(n=>n.props?.['data-group']===id);assert.equal(g.props['data-open'],true);let stopped=false;walk(g).find(n=>n.props?.['aria-controls']).props.onClick({stopPropagation(){stopped=true;}});assert.equal(stopped,true);assert.deepEqual(h.actions,[dest]);}});
