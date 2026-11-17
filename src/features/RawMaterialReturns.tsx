import {useEffect,useRef,useState} from 'react';
import {Dialog,formatTime} from '@/components/ui';
import EntityCombobox from '@/components/EntityCombobox';
import {decimalCompare} from '@/utils/quality-quantities.mjs';
import type {FeatureProps} from './types';
type Choice={material:string;name:string;name_ar:string;unit:string;line:string;line_name:string;line_name_ar:string;available:string};
export type RawReturn={id:string;code:string;material_id:string;name:string;name_ar:string;unit:string;source_name:string;source_name_ar:string;warehouse_name:string;warehouse_name_ar:string;requested:string|number;received:string|number;outstanding:string;status:string;revision:number;note:string;created_at:string;created_by:string;allocations:{request:string;item:string;code:string;quantity:string;received:string}[];events?:{operation:string;created_at:string;quantity:string|null;actor:string}[]};
type Context={rows:Choice[];warehouses:{id:string;name:string;name_ar:string}[]};
const local=(name:string,ar:string,lang:string)=>lang==='ar'?ar||name:name;
function useReturnCommand(factory:string){const [busy,setBusy]=useState(false),[error,setError]=useState(''),lock=useRef(false),retry=useRef<{key:string;id:string}|null>(null);return{busy,error,run:async(operation:string,payload:Record<string,unknown>)=>{if(lock.current)return null;const key=JSON.stringify([factory,operation,payload]);if(retry.current?.key!==key)retry.current={key,id:crypto.randomUUID()};lock.current=true;setBusy(true);setError('');try{const r=await fetch('/api/material-returns',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({factory,operation,payload,request_id:retry.current.id}),signal:AbortSignal.timeout(25000)}),b=await r.json();if(!r.ok)throw Error(b.error||'dataWarning');retry.current=null;return b.data as RawReturn;}catch(e){setError(e instanceof Error?e.message:'dataWarning');return null;}finally{lock.current=false;setBusy(false);}}};}

export function MaterialReturnReceipt({props,row,onChanged}:{props:FeatureProps;row:RawReturn;onChanged:()=>void}){
 const {t,lang,can,snapshot:s}=props,[current,setCurrent]=useState(row),[quantity,setQuantity]=useState(row.outstanding),[physical,setPhysical]=useState(false),action=useReturnCommand(String(s.factory?.id||''));
 const [historyError,setHistoryError]=useState('');
 useEffect(()=>{const a=new AbortController();setHistoryError('');fetch('/api/material-returns?'+new URLSearchParams({factory:String(s.factory?.id||''),audience:'WAREHOUSE',request:row.id}),{signal:a.signal,cache:'no-store'}).then(async r=>{const b=await r.json();if(!r.ok)throw Error(b.error||'dataWarning');if(!a.signal.aborted&&b.data.rows[0])setCurrent(b.data.rows[0]);}).catch(e=>{if(e.name!=='AbortError')setHistoryError(e.message);});return()=>a.abort();},[s.factory?.id,row.id,current.revision]);
 const valid=decimalCompare(quantity,'0')===1&&(decimalCompare(quantity,current.outstanding)??1)<=0;
 return <section className="material-preparation raw-return-receipt"><strong><bdi>{current.code}</bdi> · {local(current.name,current.name_ar,lang)}</strong>
  <p>{local(current.source_name,current.source_name_ar,lang)} → {local(current.warehouse_name,current.warehouse_name_ar,lang)}</p>
  <dl className="wv-values">{[['rawReturnRequested',current.requested],['rawReturnReceived',current.received],['rawReturnOutstanding',current.outstanding]].map(([label,value])=><div key={label}><dt>{t(String(label))}</dt><dd><bdi>{String(value)} {t(current.unit)}</bdi></dd></div>)}</dl>
  <p role="status">{t('rawReturnState_'+current.status)}</p>{current.note&&<p dir="auto">{current.note}</p>}
  <details><summary>{t('rawReturnOrigins')}</summary><ul>{current.allocations.map(a=><li key={a.request}><bdi>{a.code}</bdi> · <bdi>{a.quantity} {t(current.unit)}</bdi></li>)}</ul></details>
  <details><summary>{t('rawReturnHistory')}</summary>{historyError?<p role="alert">{t(historyError)}</p>:<ol>{current.events?.map((e,i)=><li key={i}>{t('rawReturnEvent_'+e.operation)} · {e.actor} · {e.quantity&&<bdi>{e.quantity} {t(current.unit)} · </bdi>}{formatTime(e.created_at,lang,String(s.factory?.timezone||'UTC'))}</li>)}</ol>}</details>
  {can('warehouse','issue')&&['REQUESTED','PARTIALLY_RECEIVED'].includes(current.status)&&<form className="material-preparation" onSubmit={async e=>{e.preventDefault();if(!valid||!physical)return;const value=await action.run('RECEIVE',{id:current.id,revision:current.revision,quantity,physical_confirmation:true});if(value){setCurrent(value);setQuantity(value.outstanding);setPhysical(false);onChanged();}}}>
   <fieldset disabled={action.busy}><label>{t('rawReturnActualQuantity')} ({t(current.unit)})<input type="number" step="any" inputMode="decimal" min="0.000001" max={current.outstanding} required value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
    <label className="recording-confirm"><input type="checkbox" checked={physical} required onChange={e=>setPhysical(e.target.checked)}/>{t('rawReturnPhysical')}</label><p className="muted">{t('rawReturnReceiptHelp')}</p><button className="primary" disabled={!valid||!physical}>{action.busy?t('recordingSaving'):t('rawReturnReceive')}</button></fieldset>
  </form>}{action.error&&<p role="alert">{t(action.error)}</p>}
 </section>;
}

export default function RawMaterialReturns({props}:{props:FeatureProps}){
 const {t,lang,can,snapshot:s}=props,[open,setOpen]=useState(false),[context,setContext]=useState<Context|null>(null),[rows,setRows]=useState<RawReturn[]>([]),[page,setPage]=useState(1),[total,setTotal]=useState(0),[reload,setReload]=useState(0),[loading,setLoading]=useState(false),[error,setError]=useState('');
 const [material,setMaterial]=useState(''),[line,setLine]=useState(''),[warehouse,setWarehouse]=useState(''),[quantity,setQuantity]=useState(''),[note,setNote]=useState(''),[created,setCreated]=useState<RawReturn|null>(null),[cancel,setCancel]=useState(''),[reason,setReason]=useState('');
 const factory=String(s.factory?.id||''),action=useReturnCommand(factory),canCreate=can('orders','edit');
 useEffect(()=>{if(!open)return;const a=new AbortController();setLoading(true);setError('');Promise.all([fetch('/api/material-returns?'+new URLSearchParams({factory,mode:'context'}),{signal:a.signal,cache:'no-store'}),fetch('/api/material-returns?'+new URLSearchParams({factory,audience:'PRODUCTION',page:String(page)}),{signal:a.signal,cache:'no-store'})]).then(async responses=>{const values=await Promise.all(responses.map(r=>r.json()));for(let i=0;i<responses.length;i++)if(!responses[i].ok)throw Error(values[i].error||'dataWarning');if(!a.signal.aborted){setContext(values[0].data);setRows(values[1].data.rows);setTotal(values[1].data.total);}}).catch(e=>{if(e.name!=='AbortError')setError(e.message);}).finally(()=>{if(!a.signal.aborted)setLoading(false);});return()=>a.abort();},[factory,open,page,reload]);
 const materials=[...new Map(context?.rows.map(r=>[r.material,{id:r.material,label:local(r.name,r.name_ar,lang)}])||[]).values()],lines=context?.rows.filter(r=>r.material===material)||[],choice=lines.find(r=>r.line===line);
 const destination=warehouse||(context?.warehouses.length===1?context.warehouses[0].id:'');const valid=!!choice&&!!destination&&decimalCompare(quantity,'0')===1&&(decimalCompare(quantity,choice.available)??1)<=0;
 if(!can('orders','view'))return null;
 return <><button type="button" onClick={()=>setOpen(true)}>{t('rawReturnOpen')}</button>{open&&<Dialog className="raw-material-return-dialog" title={t('rawReturnOpen')} t={t} busy={action.busy} onClose={()=>{if(!action.busy)setOpen(false);}}>
  {created?<p role="status" className="notice">{t('rawReturnCreated')} <bdi>{created.code}</bdi></p>:<p>{t('rawReturnHelp')}</p>}
  {loading&&<p role="status">{t('loading')}</p>}{error&&<p role="alert">{t(error)} <button onClick={()=>setReload(n=>n+1)}>{t('refresh')}</button></p>}
  {canCreate&&context&&<form className="material-preparation" onSubmit={async e=>{e.preventDefault();if(!valid||!choice)return;const value=await action.run('CREATE',{material,line,warehouse:destination,quantity,note});if(value){setCreated(value);setQuantity('');setReload(n=>n+1);props.refreshSnapshot?.();}}}>
   <fieldset disabled={loading||action.busy}><EntityCombobox label={t('rawReturnMaterial')} options={materials} value={material} placeholder={t('select')} onChange={id=>{setMaterial(id);setLine('');setQuantity('');setCreated(null);}}/>
    <EntityCombobox label={t('rawReturnSource')} options={lines.map(r=>({id:r.line,label:local(r.line_name,r.line_name_ar,lang)}))} value={line} placeholder={t('select')} onChange={id=>{setLine(id);setQuantity('');setCreated(null);}}/>
    {context.warehouses.length===1?<p>{t('rawReturnDestination')}: {local(context.warehouses[0].name,context.warehouses[0].name_ar,lang)}</p>:<EntityCombobox label={t('rawReturnDestination')} options={context.warehouses.map(w=>({id:w.id,label:local(w.name,w.name_ar,lang)}))} value={destination} onChange={setWarehouse} placeholder={t('select')}/>}
    {choice&&<p>{t('rawReturnAvailable')}: <bdi>{choice.available} {t(choice.unit)}</bdi></p>}
    <label>{t('quantity')} ({choice?t(choice.unit):'—'})<input type="number" step="any" inputMode="decimal" min="0.000001" max={choice?.available} required value={quantity} onChange={e=>setQuantity(e.target.value)}/></label>
    <label>{t('rawReturnNote')}<textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></label>
    <button className="primary" disabled={!valid}>{action.busy?t('recordingSaving'):t('rawReturnCreate')}</button>
   </fieldset>
  </form>}{context&&!context.rows.length&&<p role="status">{t('rawReturnNone')}</p>}
  <details open={!!created}><summary>{t('rawReturnRequests')}</summary>{rows.map(row=><article className="raw-return-summary" key={row.id}><strong><bdi>{row.code}</bdi> · {local(row.name,row.name_ar,lang)}</strong><p>{t('rawReturnState_'+row.status)} · <bdi>{row.received} / {row.requested} {t(row.unit)}</bdi></p><small>{formatTime(row.created_at,lang,String(s.factory?.timezone||'UTC'))}</small>
   {canCreate&&row.created_by===s.user.id&&['REQUESTED','PARTIALLY_RECEIVED'].includes(row.status)&&<button disabled={action.busy} onClick={()=>{setCancel(row.id);setReason('');}}>{t('rawReturnCancel')}</button>}
   {cancel===row.id&&<form className="material-preparation" onSubmit={async e=>{e.preventDefault();const value=await action.run('CANCEL',{id:row.id,revision:row.revision,note:reason});if(value){setCancel('');setReload(n=>n+1);}}}><label>{t('reason')}<textarea required minLength={3} maxLength={2000} value={reason} onChange={e=>setReason(e.target.value)}/></label><button disabled={action.busy||reason.trim().length<3}>{t('confirm')}</button></form>}
  </article>)}<nav className="fulfillment-pagination"><button disabled={loading||page===1} onClick={()=>setPage(n=>n-1)}>{t('previous')}</button><span>{page}</span><button disabled={loading||page*50>=total} onClick={()=>setPage(n=>n+1)}>{t('next')}</button></nav></details>
  {action.error&&<p role="alert">{t(action.error)}</p>}
 </Dialog>}</>;
}
