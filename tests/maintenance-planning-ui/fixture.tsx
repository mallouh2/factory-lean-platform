// Actual components, read-only synthetic responses. No operational confirmations or remote client.
import React, {useState} from 'react';
import {createRoot} from 'react-dom/client';
import MaintenancePlanning from '../../src/features/MaintenancePlanning';
import ProductionPlanning from '../../src/features/ProductionPlanning';
import {MaintenanceStopChoice,MaintenanceActualStops,type StopSchedule} from '../../src/features/MaintenanceActualStops';
import ProductionStartReadiness from '../../src/features/ProductionStartReadiness';
import LossImpactReview from '../../src/features/LossImpactReview';
import en from '../../src/locales/en.json';
import ar from '../../src/locales/ar.json';
import type {FeatureProps} from '../../src/features/types';
const id=(n:number)=>`10000000-0000-0000-0000-${String(n).padStart(12,'0')}`;
const time=(n:number)=>new Date(Date.now()+n*3600000).toISOString();
function Fixture() {
  const params=new URLSearchParams(location.search);
  const [lang,setLang]=useState<'en'|'ar'>(params.get('lang')==='ar'?'ar':'en');
  const [view,setView]=useState(params.get('view') || 'queue'),[authority,setAuthority]=useState(true),[visible,setVisible]=useState(true);
  const [choice,setChoice]=useState<StopSchedule|null>(null);
  const dictionary:Record<string,string>=lang==='ar'?ar:en;
  document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';
  const props:FeatureProps={lang,t:key=>dictionary[key] || key,can:(module,action='view')=>module==='maintenance' && !visible ? false : action==='view' || authority,
    snapshot:{...params.get('truncated')?{truncatedTables:[params.get('truncated')!]}:{},factory:{id:id(1),timezone:'Asia/Riyadh'},user:{id:id(2)},membership:null,permissions:[],supportFactories:[],fetchedAt:'offline',tables:{
      work_centers:[{id:id(3),line_id:id(4),code:'EX-1',name:'Extruder',name_ar:'ماكينة البثق',dependency_mode:'blocking'},
        {id:id(5),line_id:null,code:'IN-1',name:'Independent printer',name_ar:'الطابعة المستقلة',dependency_mode:'independent'}],
      production_lines:[{id:id(4),name:'QA extrusion line',name_ar:'خط البثق التجريبي'}],
      work_center_capabilities:[{work_center_id:id(3),product_id:id(6),rate:10,rate_unit:'piece'}],production_transfers:[],production_routing_steps:[],
      products:[{id:id(6),name:'Pressure pipe',name_ar:'أنبوب ضغط'}],
      production_requests:[{id:id(7),code:'PO-QA',name:'Synthetic planning order',priority:'normal'}],
      production_orders:[{id:id(8),request_id:id(7),product_id:id(6),code:'PI-QA',status:'planned',line_id:id(4),start_time:time(1),expected_finish:time(3),target_quantity:20,unit:'piece'}],
    }},command:async(name,args)=>{
      const fixtureWindow=window as unknown as {commands:unknown[]};(fixtureWindow.commands ||= []).push({name,args});
      throw Error(new URLSearchParams(location.search).get('failure') || 'maintenanceConflict');
    }};
  return <main style={{maxWidth:1400,padding:16,margin:'auto'}} dir={lang==='ar'?'rtl':'ltr'}>
    <header className="mr-tools"><strong>Isolated local component fixture · writes rejected</strong><div className="mr-actions">
      <button onClick={()=>setLang(lang==='en'?'ar':'en')}>English / العربية</button><button onClick={()=>setAuthority(!authority)}>Edit authority: {authority?'on':'off'}</button>
      <button onClick={()=>setVisible(!visible)}>Maintenance view: {visible?'on':'off'}</button></div></header>
    <nav className="mp-views" aria-label="Fixture view"><button onClick={()=>setView('queue')}>Queue</button><button onClick={()=>setView('gantt')}>Gantt</button></nav>
    {view==='loss'?<LossImpactReview {...props} eventId={id(9)}/>:view==='readiness'?<><h3>{props.t('productionQueueReady')}</h3><ProductionStartReadiness {...props} item={id(8)} busy={false}
      onStart={async()=>{try{await props.command('start_product_item',{factory:id(1),item:id(8)});}catch{ /* Fixture rejects every write. */ }}} /></>
      :view==='stops'?<><MaintenanceStopChoice {...props} machine={id(3)} choice={choice} onChange={setChoice}/>
      <output>{choice?.code || 'Ordinary'}</output><MaintenanceActualStops {...props} id={id(100)}/></>
      :view==='queue'?<MaintenancePlanning {...props}/>:<ProductionPlanning {...props}/>}
  </main>;
}
createRoot(document.getElementById('root')!).render(<Fixture/>);
