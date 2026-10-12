// Offline visual/interaction fixture. No Supabase client, credentials or remote I/O.
import React,{useState} from 'react';
import {createRoot} from 'react-dom/client';
import Quality,{QualityNotifications} from '../../src/features/Quality';
import {SourceAllocationFields,SourceIdentityDialog} from '../../src/features/SourceStock';
import en from '../../src/locales/en.json';
import ar from '../../src/locales/ar.json';
const id=(n:number)=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
let rejected='0',accepted='100',available='100',failNext=false;
const item={id:id(1),source_id:id(2),product_id:id(3),unit:'meter',recorded_good:'100',current_good:'100',rejected,accepted,eligible:available,physical_label:'PIPE-A-001',weight_kg_per_unit:'.35',product_name:'PVC pressure pipe 25 mm',product_name_ar:'أنبوب ضغط PVC قطر ٢٥ مم',product_code:'PVC-25',request_code:'PR-0044',item_code:'PI-0044-01',line_name:'Extrusion line 1',line_name_ar:'خط البثق ١',shift_name:'Night shift',shift_name_ar:'الوردية الليلية',shift_date:'2026-10-09',factory_timezone:'Asia/Riyadh',created_at:'2026-10-10T00:00:00Z'};
let records:Record<string,unknown>[]=[];
const reasonRows=[{id:id(6),name:'Dimensional defect',name_ar:'عيب في الأبعاد',active:true,is_other:false},
 ...Array.from({length:105},(_,n)=>({id:id(100+n),name:'Reason '+String(n).padStart(3,'0'),name_ar:'سبب '+String(n).padStart(3,'0'),active:true,is_other:false})),
 ...Array.from({length:110},(_,n)=>({id:id(300+n),name:'Archived '+n,name_ar:'مؤرشف '+n,active:false,is_other:false})),
 {id:id(7),name:'Other',name_ar:'أخرى',is_other:true,active:true}];
function fixtureReasons(url:URL){
 const page=Number(url.searchParams.get('page')||1),search=(url.searchParams.get('search')||'').toLowerCase();
 if(url.searchParams.get('active_only')!=='true')return{rows:reasonRows.slice((page-1)*100,page*100)};
 const matches=reasonRows.filter(r=>r.active&&!r.is_other&&[r.name,r.name_ar].some(n=>n.toLowerCase().includes(search)));
 const rows=matches.slice((page-1)*100,page*100);
 return{rows:[...rows,...reasonRows.filter(r=>r.active&&(r.is_other||r.id===url.searchParams.get('selected'))&&!rows.includes(r))],total:matches.length,page_size:100};
}
globalThis.fetch=async input=>{
 const url=new URL(String(input),'http://127.0.0.1');
 if(url.pathname!=='/api/quality')throw Error('Offline fixture denies all other endpoints');
 const mode=url.searchParams.get('mode');
 const data=mode==='sources'?{rows:[{id:id(2),physical_label:'PIPE-A-001',selectable:available,available,identifiable:'25'}],unattributed:'20',required_quantity:null,total:1}:
 mode==='filters'?{products:[{id:id(3),name:item.product_name,name_ar:item.product_name_ar}],lines:[{id:id(4),name:item.line_name,name_ar:item.line_name_ar}],shifts:[{id:id(5),name:item.shift_name,name_ar:item.shift_name_ar}]}:
 mode==='reasons'?fixtureReasons(url):
 mode==='detail'?records.find(r=>r.id===url.searchParams.get('rejection')):
 mode==='notifications'||mode==='history'?{rows:records,total:records.length}:
 {rows:[{...item,rejected,accepted,eligible:available}],total:1,quality_scrap_kg:String(records.reduce((sum,row)=>sum+Number(row.actual_scrap_kg||0),0))};
 return new Response(JSON.stringify(data),{status:200,headers:{'Content-Type':'application/json'}});
};
function Fixture(){
 const [lang,setLang]=useState<'en'|'ar'>('en'),[view,setView]=useState('quality'),[identity,setIdentity]=useState(false),[readOnly,setReadOnly]=useState(false),[revision,setRevision]=useState(0),[pickState,setPickState]=useState('');
 const dict:Record<string,string>=lang==='ar'?ar:en;
 const props={lang,t:(k:string)=>dict[k]||k,can:(_m:string,action='view')=>!readOnly||action==='view',
 snapshot:{factory:{id:id(9),timezone:'Asia/Riyadh'},user:{id:id(8)},membership:null,permissions:[],supportFactories:[],fetchedAt:String(revision),tables:{products:[],production_lines:[],production_shifts:[]}},
 command:async(name:string,args:Record<string,unknown>)=>{
  await new Promise(r=>setTimeout(r,250));if(failNext){failNext=false;throw Error('qualityUnavailable');}
  const p=args.payload as Record<string,unknown>;
  if(name==='quality_command'&&args.operation==='reject'){
   const qty=Number(p.quantity);rejected=String(Number(rejected)+qty);accepted=String(Number(accepted)-qty);available=String(Number(available)-qty);
   records=[{...item,...p,id:crypto.randomUUID(),actual_scrap_kg:p.actual_scrap_kg,default_scrap_kg:String(qty*.35),shortfall:String(qty),reason:p.reason===id(7)?'Other':'Dimensional defect',reason_ar:p.reason===id(7)?'أخرى':'عيب في الأبعاد',actor_name:'Quality inspector',notification:{status:'OPEN'},lots:[],created_at:new Date().toISOString()},...records];
  }
  setRevision(r=>r+1);return records[0]?.id||id(10);
 }};
 return <main style={{maxWidth:1240,margin:'auto',padding:16}} dir={lang==='ar'?'rtl':'ltr'}>
  <header className="section-head" style={{flexWrap:'wrap'}}><div><strong>Quality V1 — offline component verification</strong><p className="muted">Synthetic data. No database connection.</p></div>
   <div className="row-actions"><button onClick={()=>setLang(lang==='en'?'ar':'en')}>English / العربية</button><button onClick={()=>setView(view==='quality'?'warehouse':'quality')}>Quality / Warehouse</button><label><input type="checkbox" checked={readOnly} onChange={e=>setReadOnly(e.target.checked)}/>View only</label><button onClick={()=>{failNext=true;}}>Fail next submission</button></div></header>
  {view==='quality'?<><Quality {...props}/><QualityNotifications {...props}/></>:<><h2>{props.t('sourceSelection')}</h2><SourceAllocationFields {...props} product={id(3)} unit="meter" quantity="10" onChange={(p,valid)=>setPickState(JSON.stringify({p,valid}))}/><p role="status">{pickState}</p><button onClick={()=>setIdentity(true)}>{props.t('sourceIdentify')}</button></>}
  {identity&&<SourceIdentityDialog {...props} product={id(3)} unit="meter" entry={id(1)} onClose={()=>setIdentity(false)} onChanged={()=>setRevision(r=>r+1)}/>}
 </main>;
}
createRoot(document.getElementById('root')!).render(<Fixture/>);
