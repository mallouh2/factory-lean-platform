// Real component; synthetic loopback HTTP fixture only. No Supabase session.
import React,{useEffect,useState} from 'react';
import {createRoot} from 'react-dom/client';
import ProductionRecordingV3 from '../../src/features/ProductionRecordingV3';
import en from '../../src/locales/en.json';
import ar from '../../src/locales/ar.json';
import type {FeatureProps} from '../../src/features/types';
import '../../src/features/production-recording-v3.css';
const params=new URLSearchParams(location.search),caseName=params.get('case')||'normal';
const id=(n:number)=>`10000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
const nativeFetch=window.fetch.bind(window);
window.fetch=async(input,options)=>{const url=new URL(String(input),location.href);if(url.origin!==location.origin)throw Error('External network forbidden');url.searchParams.set('fixture',caseName);const response=await nativeFetch(url,options);if(options?.method==='POST'&&caseName.includes('drop'))throw Error('Controlled lost response after server commit');return response};
function Fixture(){
 const [lang,setLang]=useState<'en'|'ar'>(()=>params.get('lang')==='ar'||localStorage.getItem('factory-language')==='ar'?'ar':'en');
 useEffect(()=>{document.documentElement.lang=lang;document.documentElement.dir=lang==='ar'?'rtl':'ltr';localStorage.setItem('factory-language',lang)},[lang]);
 const dictionary:Record<string,string>=lang==='ar'?ar:en;
 const props:FeatureProps={lang,t:key=>dictionary[key]||key,onLanguageChange:()=>setLang(v=>v==='ar'?'en':'ar'),refreshSnapshot:async()=>{},can:(_module,action)=>action==='view'||!caseName.includes('denied'),
  snapshot:{factory:{id:id(1),timezone:'Asia/Riyadh'},user:{id:id(2)},membership:null,permissions:[],supportFactories:[],fetchedAt:'isolated',tables:{
   production_technicians:[{id:id(3),user_id:id(2),display_name:'Local technician'}],production_lines:[{id:id(4),name:'QA line',name_ar:'الخط التجريبي'}],products:[{id:id(5),name:'Pressure pipe',name_ar:'أنبوب ضغط'}],production_requests:[{id:id(6),code:'PO-LOCAL-1'}],production_orders:[{id:id(7),request_id:id(6),product_id:id(5),status:'in_progress',line_id:id(4),target_quantity:100,good_quantity:0,unit:'meter'}],production_recording_units:[{unit_kind:'line',unit_id:id(4),item_id:id(7)}],production_entries:[],production_shifts:[]}},
  command:async()=>{throw Error('Only recording through the protected client is allowed')}};
 return <main style={{padding:24,maxWidth:1440,margin:'auto'}}><p>Isolated local component fixture · synthetic records only</p><ProductionRecordingV3 {...props}/></main>;
}
createRoot(document.getElementById('root')!).render(<Fixture/>);
