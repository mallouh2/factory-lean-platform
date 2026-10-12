import { useEffect,useRef,useState } from 'react';
import { Dialog,Field } from '@/components/ui';
import type { FeatureProps,Command } from './types';
import { useSupply } from './useSupply';
import { decimalCompare,decimalSubtract,quantityValid } from '@/utils/quality-quantities.mjs';
export type SourcePick={source_id:string|null;quantity:string;sales_line_id?:string};
type SourceRow={id:string;physical_label:string|null;selectable:string;identifiable:string;available:string};
type SourcePage={rows:SourceRow[];unattributed:string;required_quantity:string|null;total:number};
export function useSourceStockCommand(command:Command,factory:unknown){
 const retry=useRef<{key:string;id:string}|null>(null),submitting=useRef(false);
 const [busy,setBusy]=useState(false),[error,setError]=useState('');
 async function run(operation:string,payload:Record<string,unknown>,allocations:SourcePick[]=[]){
  if(submitting.current)return false;
  const key=JSON.stringify([factory,operation,payload,allocations]);if(retry.current?.key!==key)retry.current={key,id:crypto.randomUUID()};
  submitting.current=true;setBusy(true);setError('');
  try{await command('source_stock_command',{factory,operation,payload,allocations,request_id:retry.current.id});retry.current=null;return true;}
  catch(cause){setError(cause instanceof Error?cause.message:'error');return false;}
  finally{submitting.current=false;setBusy(false);}
 }
 return {run,busy,error,clearError:()=>setError('')};
}
export function SourceAllocationFields({snapshot,t,lang,product,unit,quantity,salesLine,entry,materialRequest,disabled=false,onChange}:Pick<FeatureProps,'snapshot'|'t'|'lang'>&
 {product:string;unit:string;quantity:string;salesLine?:string;entry?:string;materialRequest?:string;disabled?:boolean;onChange:(picks:SourcePick[],valid:boolean)=>void}){
 const [page,setPage]=useState(1),[draft,setDraft]=useState<{selection:string;quantity:string;source?:SourceRow}[]>([{selection:'',quantity}]);
 const read=useSupply<SourcePage>(snapshot,'sources',{product,unit,page:String(page),...(salesLine?{sales_line:salesLine}:{}),...(entry?{entry}:{}),...(materialRequest?{material_request:materialRequest}:{})},!!product,'/api/quality');
 const callback=useRef(onChange);useEffect(()=>{callback.current=onChange;},[onChange]);
 useEffect(()=>{setDraft([{selection:'',quantity}]);setPage(1);},[product,unit,quantity,salesLine,entry,materialRequest]);
 const required=read.data?.required_quantity??quantity;
 useEffect(()=>{if(read.data?.required_quantity)setDraft(old=>old.length===1&&!old[0].selection&&old[0].quantity===quantity?[{...old[0],quantity:read.data!.required_quantity!}]:old);},[read.data?.required_quantity,quantity]);
 useEffect(()=>{
  let remaining=required;const totals=new Map<string,string>();
  const picks=draft.filter(p=>p.selection).map(p=>({source_id:p.selection==='unattributed'?null:p.selection,quantity:p.quantity,...(salesLine?{sales_line_id:salesLine}:{})}));
  let valid=!!read.data&&!read.busy&&!read.error&&draft.length>0;
  for(const row of draft){
   const source=read.data?.rows.find(s=>s.id===row.selection)||row.source;
   const available=row.selection==='unattributed'?read.data?.unattributed:source?.selectable;
   valid=valid&&!!row.selection&&available!==undefined&&quantityValid(row.quantity,unit,available);
   remaining=decimalSubtract(remaining,row.quantity)??'invalid';
   const previous=totals.get(row.selection)||'0';
   const combined=decimalSubtract(previous,'-'+row.quantity)??'invalid';totals.set(row.selection,combined);
   valid=valid&&available!==undefined&&decimalCompare(combined,available)!==null&&decimalCompare(combined,available)!==1;
  }
  callback.current(picks,valid&&decimalCompare(remaining,'0')===0);
 },[draft,read.data,read.busy,read.error,required,unit,salesLine]);
 return <fieldset disabled={disabled} className="source-allocation" dir={lang==='ar'?'rtl':'ltr'}>
  <h4>{t('sourceSelection')}</h4><p className="muted">{t('sourcePhysicalHelp')}</p><p>{t('quantity')}: <strong>{required} {t(unit)}</strong></p>
  {read.error&&<p role="alert">{t(read.error)} <button type="button" onClick={read.refresh}>{t('refresh')}</button></p>}
  {read.busy&&<p role="status">{t('loading')}</p>}
  {draft.map((row,index)=>{
   const choices=[...(read.data?.rows||[]),...(row.source&&!read.data?.rows.some(s=>s.id===row.source?.id)?[row.source]:[])];
   return <div className="source-pick-row" key={index}>
    <Field label={`${t('sourceLabel')} ${index+1}`}><select required value={row.selection} onChange={e=>setDraft(old=>old.map((p,i)=>i===index?{...p,selection:e.target.value,source:choices.find(s=>s.id===e.target.value)}:p))}>
     <option value="">{t('select')}</option><option value="unattributed">{t('sourceUnattributed')} · {read.data?.unattributed||'0'} {t(unit)}</option>
     {choices.filter(s=>s.physical_label).map(s=><option key={s.id} value={s.id}>{s.physical_label} · {s.selectable} {t(unit)}</option>)}
    </select></Field>
    <Field label={t('quantity')}><input required type="number" inputMode="decimal" min="0" step={unit==='piece'?'1':'any'} value={row.quantity} onChange={e=>setDraft(old=>old.map((p,i)=>i===index?{...p,quantity:e.target.value}:p))}/></Field>
    {draft.length>1&&<button type="button" aria-label={t('sourceRemovePick')} onClick={()=>setDraft(old=>old.filter((_,i)=>i!==index))}>×</button>}
   </div>;
  })}
  <div className="row-actions"><button type="button" disabled={read.busy} onClick={read.refresh}>{t('refresh')}</button><button type="button" disabled={draft.length>=100} onClick={()=>setDraft(old=>[...old,{selection:'',quantity:''}])}>{t('sourceAddPick')}</button>
   <button type="button" disabled={page===1||read.busy} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button type="button" disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></div>
 </fieldset>;
}
export function SourceIdentityDialog(props:FeatureProps&{product:string;unit:string;entry:string;onClose:()=>void;onChanged:()=>void}){
 const {snapshot,t,product,unit,entry}=props;
 const read=useSupply<SourcePage>(snapshot,'sources',{product,unit,entry},true,'/api/quality'),action=useSourceStockCommand(props.command,snapshot.factory?.id);
 const [quantity,setQuantity]=useState(''),[label,setLabel]=useState(''),[identified,setIdentified]=useState(false);
 const [operation,setOperation]=useState('identify'),[note,setNote]=useState('');
 const source=read.data?.rows[0];
 const maximum=operation==='mix'?source?.selectable:source?.identifiable;
 return <Dialog busy={action.busy} title={t('sourceIdentify')} t={t} onClose={()=>{if(!action.busy)props.onClose();}}>
  <p>{t('sourceIdentifyHelp')}</p>{read.error&&<p role="alert">{t(read.error)}</p>}
  {read.busy?<p role="status">{t('loading')}</p>:!source?<p>{t('sourceHistoricalHelp')}</p>:<form onSubmit={async e=>{e.preventDefault();if(!quantityValid(quantity,unit,maximum)||!identified)return;
   if(await action.run(operation,{source:source.id,quantity,...(operation==='identify'?{label:source.physical_label||label}:{}),note,physically_identified:identified})){props.onChanged();props.onClose();}
  }}><fieldset disabled={action.busy}>
   <Field label={t('actions')}><select value={operation} onChange={e=>{setOperation(e.target.value);setQuantity('');setIdentified(false);action.clearError();}}><option value="identify">{t('sourceIdentify')}</option><option value="mix" disabled={!source.physical_label}>{t('sourceMarkMixed')}</option></select></Field>
   <p>{t(operation==='mix'?'sourceMixedHelp':'sourceNotIdentified')}: {maximum} {t(unit)}</p>
   <Field label={t('sourceLabel')}><input required maxLength={200} value={source.physical_label||label} readOnly={!!source.physical_label} onChange={e=>setLabel(e.target.value)}/></Field>
   <Field label={t('quantity')}><input required type="number" inputMode="decimal" min="0" step={unit==='piece'?'1':'any'} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
   <Field label={t('notes')}><textarea maxLength={2000} value={note} onChange={e=>setNote(e.target.value)}/></Field>
   <label className="recording-confirm"><input type="checkbox" checked={identified} onChange={e=>setIdentified(e.target.checked)}/>{t(operation==='mix'?'sourceMixedConfirm':'sourcePhysicalConfirm')}</label>
   {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary" disabled={!identified||!quantityValid(quantity,unit,maximum)}>{t(operation==='mix'?'sourceMarkMixed':'sourceIdentify')}</button>
  </fieldset></form>}
 </Dialog>;
}
