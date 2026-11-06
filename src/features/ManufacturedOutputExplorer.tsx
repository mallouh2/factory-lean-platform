import {useEffect,useState} from 'react';
import {Dialog} from '@/components/ui';
import type {FeatureProps,OutputDestination} from './types';
import type {Row} from '@/types';
import ManufacturedOutput from './ManufacturedOutput';
import ManufacturedReceiving from './ManufacturedReceiving';
import ManufacturedCompletion from './ManufacturedCompletion';
import ProductionOrdersV2 from './ProductionOrdersV2';
import {outputDestinationAllowed} from '@/utils/output-navigation.mjs';
function OriginalOrder(props:FeatureProps&{item:string;onSchedule:(id:string)=>void}){
 const f=String(props.snapshot.factory?.id||''),[data,setData]=useState<{available:boolean;item:Row|null;request:Row;product:Row}|null>(null),[error,setError]=useState(false),[retry,setRetry]=useState(0);
 useEffect(()=>{const a=new AbortController();setData(null);setError(false);fetch('/api/manufactured-output?'+new URLSearchParams({factory:f,mode:'order',target:props.item}),{cache:'no-store',signal:a.signal}).then(async r=>{if(!r.ok)throw Error();setData(await r.json());}).catch(e=>{if(e.name!=='AbortError')setError(true);});return()=>a.abort();},[f,props.item,retry]);
 if(error)return <p role="alert">{props.t('dataWarning')} <button onClick={()=>setRetry(n=>n+1)}>{props.t('retry')}</button></p>;
 if(!data)return <p role="status">{props.t('loading')}</p>;
 if(!data.available||!data.item||!data.request)return <p role="status">{props.t('notAvailable')}</p>;
 const tables={...props.snapshot.tables,production_orders:[data.item],production_requests:[data.request],products:[...props.snapshot.tables.products.filter(p=>p.id!==data.product?.id),...(data.product?[data.product]:[])]};
 return <><p>{props.lang==='ar'?'يعرض هذا السياق بند الإنتاج المرتبط فقط. التقدم من تسجيل الفني الأصلي؛ قرار الجودة والمخزون المستلم حقائق منفصلة.':'This context shows only the linked Production Item. Progress is technician-recorded history; Quality classification and received inventory are separate facts.'}</p><ProductionOrdersV2 {...props} snapshot={{...props.snapshot,tables}} initialItemId={props.item} onPlanItem={props.onSchedule}/></>;
}
export default function ManufacturedOutputExplorer(props:FeatureProps&{target:OutputDestination;onClose:()=>void;onSchedule:(id:string)=>void}){
 const [path,setPath]=useState([props.target]),d=path[path.length-1],ar=props.lang==='ar',f=String(props.snapshot.factory?.id||'');
 const words={production:['Production details','تفاصيل الإنتاج'],quality:['Quality inspection','فحص الجودة'],warehouse:['Production receipt','استلام الإنتاج'],planning:['Recovery / replacement work','أعمال الإكمال / التعويض'],order:['Original Production Order','أمر الإنتاج الأصلي']};
 const childProps={...props,onOutputRelated:(next:OutputDestination)=>{if(outputDestinationAllowed(next,f,props.can))setPath(p=>[...p,next]);}};
 return <Dialog title={words[d.view][ar?1:0]} t={props.t} onClose={props.onClose} className="prv3-dialog output-related-dialog" headerActions={props.onLanguageChange&&<button type="button" onClick={props.onLanguageChange}>{ar?'English':'العربية'}</button>}><div className={'prv3-body '+(['warehouse','planning'].includes(d.view)?'warehouse-v1':'')} dir={ar?'rtl':'ltr'}>
  {path.length>1&&<button type="button" onClick={()=>setPath(p=>p.slice(0,-1))}>{ar?'رجوع إلى السجل السابق':'Back to previous record'}</button>}
  {!outputDestinationAllowed(d,f,props.can)?<p role="alert">{props.t('noPermission')}</p>:d.view==='production'?<ManufacturedOutput {...childProps} entry={d.entry} related/>:d.view==='quality'?<ManufacturedOutput {...childProps} focusEntry={d.entry}/>:d.view==='warehouse'?<ManufacturedReceiving {...childProps} focusOutput={d.output}/>:d.view==='planning'?<ManufacturedCompletion {...childProps} focusOutput={d.output} focusWork={d.work} onWork={()=>{}} onSchedule={props.onSchedule}/>:<OriginalOrder {...childProps} item={d.item!} onSchedule={props.onSchedule}/>}
 </div></Dialog>;
}
