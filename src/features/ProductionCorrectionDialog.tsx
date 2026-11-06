import {useEffect,useState} from 'react';
import {Dialog,Field} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import {correctionDraft,correctionPayload,correctionReasonSuggestions} from '@/utils/production-correction-ui.mjs';
import {decimalCompare,decimalSubtract} from '@/utils/quality-quantities.mjs';
import {historyNumber} from '@/utils/production-history-view.mjs';
import {recordingNumber} from '@/utils/production-recording-intent.mjs';
import {SourceAllocationFields,type SourcePick} from './SourceStock';
import {outputText} from './ManufacturedOutput';
import {useCorrectionAction,type CorrectionRequest} from './useCorrectionAction';
import type {FeatureProps} from './types';
type Context=Record<string,string|null>&{id:string;factory_id:string;unit:string;good:string;unfinished:string;correction_revision:string};
export default function ProductionCorrectionDialog(props:FeatureProps&{entry:string;onClose:()=>void;onChanged:()=>void}){
 const {snapshot:s,t,lang,can,entry,onClose,onChanged}=props,factory=String(s.factory?.id||'');
 const read=useHistoryData<Context>('/api/production-corrections?'+new URLSearchParams({factory,context_entry:entry}),entry);
 const [draft,setDraft]=useState<Record<string,string>>({}),[picks,setPicks]=useState<SourcePick[]>([]),[picksValid,setPicksValid]=useState(false),[confirmed,setConfirmed]=useState(false),[receipt,setReceipt]=useState<CorrectionRequest|null>(null);
 const action=useCorrectionAction(s.user.id,factory,row=>{setReceipt(row);onChanged();});
 useEffect(()=>{if(read.data){setDraft(correctionDraft(read.data));setPicks([]);setPicksValid(false);setConfirmed(false);}},[read.data]);
 const context=read.data,eligible=can('orders','view')&&(can('orders','edit')||can('orders','approve'));
 const unit=t(context?.unit==='piece'?'pieceShort':context?.unit==='meter'?'meterShort':context?.unit==='kg'?'kg':'legacyUnit');
 const quantity=(value:unknown,kg=false)=>`${historyNumber(value,lang)??t('notAvailable')} ${kg?t('kg'):unit}`;
 let normalizedGood='';try{normalizedGood=recordingNumber(draft.good);}catch{/* Incomplete input. */}
 const preReceipt=String(context?.output_pre_receipt)==='true';
 const decrease=context&&!preReceipt&&decimalCompare(normalizedGood,context.good)===-1;
 const locked=action.busy||!!action.pending;
 const change=(key:string,value:string)=>setDraft(old=>({...old,[key]:value}));
 let valid=false;try{if(context){correctionPayload(context,draft,picks,confirmed);valid=draft.reason.trim().length>=3&&draft.reason.length<=2000&&(!decrease||picksValid)&&decimalCompare(draft.startup_kg,draft.scrap_kg)!==1&&(!(decimalCompare(draft.unfinished,'0')===1)||draft.remaining_work.trim().length>=3);}}catch{/* Preserve incomplete input. */}
 return <Dialog title={t('pcRequest')} t={t} busy={action.busy} className="pc-dialog" onClose={onClose} headerActions={props.onLanguageChange&&<button onClick={props.onLanguageChange}>{lang==='ar'?'English':'العربية'}</button>}>
  <div className="pc-body" dir={lang==='ar'?'rtl':'ltr'}>
   {!eligible?<p role="alert">{t('permissionError')}</p>:<>
   {read.loading&&<p role="status">{t('loading')}</p>}
   {read.error&&<p role="alert">{t(read.error)} <button onClick={read.reload}>{t('refresh')}</button></p>}
   {context&&(!receipt||receipt.entry_id===entry)&&<header><strong><bdi>{context.request_code} · {context.item_code}</bdi></strong><p dir="auto">{lang==='ar'?context.product_name_ar||context.product_name:context.product_name}</p></header>}
   {receipt?<div role="status"><h3>{t(receipt.status==='PENDING'?'pcPendingSuccess':'pcApprovedSuccess')}</h3><p>{t('pcOfficialNow')}: <bdi>{quantity((receipt.applied_values||receipt.original_values).good)}</bdi> · {t('historyScrap')}: <bdi>{quantity((receipt.applied_values||receipt.original_values).scrap_kg,true)}</bdi></p><button className="primary" onClick={onClose}>{t('close')}</button></div>:
   context&&<form onSubmit={e=>{e.preventDefault();if(!valid||!eligible||locked)return;void action.run('submit',correctionPayload(context,draft,picks,confirmed));}}>
    <fieldset disabled={locked||!eligible||read.loading||!!read.error}>
     {preReceipt&&<p role="status">{outputText(lang,'correction')}</p>}<div className="pc-quantity-grid">
      <Field label={t('pcProposedGood')+' ('+unit+')'}><small>{t('pcOfficial')}: <bdi>{quantity(context.good)}</bdi></small><input required inputMode="decimal" value={draft.good||''} onChange={e=>{change('good',e.target.value);setConfirmed(false);}}/></Field>
      <Field label={t('pcProposedScrap')+' ('+t('kg')+')'}><small>{t('pcOfficial')}: <bdi>{quantity(context.scrap_kg,true)}</bdi></small><input required inputMode="decimal" value={draft.scrap_kg??''} onChange={e=>change('scrap_kg',e.target.value)}/></Field>
     </div>
     {context.scrap_kg===null&&<p>{t('leanLegacyScrapHelp')}</p>}
     {(context.input_lot_id||decimalCompare(context.unfinished,'0')===1)&&<div className="pc-support">
      <Field label={t('unfinishedQuantity')+' ('+unit+')'}><input disabled={preReceipt} required inputMode="decimal" value={draft.unfinished||''} onChange={e=>change('unfinished',e.target.value)}/></Field>
      <Field label={t('unfinishedRemainingWork')}><input disabled={preReceipt} maxLength={2000} value={draft.remaining_work||''} onChange={e=>change('remaining_work',e.target.value)}/></Field>
      {context.input_lot_id&&<><p>{t('unfinishedConservationHelp')} · <bdi>{quantity(context.input_quantity)}</bdi></p><Field label={t('leanDiscardedQuantity')+' ('+unit+')'}><input required inputMode="decimal" value={draft.discarded_quantity||''} onChange={e=>change('discarded_quantity',e.target.value)}/></Field></>}
     </div>}
     {!context.input_lot_id&&decimalCompare(context.unfinished,'0')!==1&&<details><summary>{t('pcOtherQuantities')}</summary>
      <Field label={t('unfinishedQuantity')+' ('+unit+')'}><input disabled={preReceipt} required inputMode="decimal" value={draft.unfinished||''} onChange={e=>change('unfinished',e.target.value)}/></Field>
      {decimalCompare(draft.unfinished,'0')===1&&<Field label={t('unfinishedRemainingWork')}><input minLength={3} maxLength={2000} value={draft.remaining_work||''} onChange={e=>change('remaining_work',e.target.value)}/></Field>}
     </details>}
     {decimalCompare(context.startup_kg,'0')===1&&<Field label={t('leanStartupIncluded')+' ('+t('kg')+')'}><input required inputMode="decimal" value={draft.startup_kg||''} onChange={e=>change('startup_kg',e.target.value)}/></Field>}
     <Field label={t('pcReason')}><textarea required minLength={3} maxLength={2000} value={draft.reason||''} onChange={e=>change('reason',e.target.value)}/></Field>
     {!!draft.reason&&draft.reason.trim().length<3&&<p role="alert">{t('pcReasonRequired')}</p>}
     <div className="pc-suggestions" aria-label={t('pcSuggestions')}>{correctionReasonSuggestions.map(key=><button key={key} type="button" onClick={()=>change('reason',t(key))}>{t(key)}</button>)}</div>
     {decrease&&<SourceAllocationFields disabled={locked} snapshot={s} t={t} lang={lang} product={String(context.product_id)} unit={context.unit} entry={entry} quantity={decimalSubtract(context.good,normalizedGood)||''} onChange={(rows,ok)=>{setPicks(rows);setPicksValid(ok);}}/>}
     {decimalCompare(draft.good,context.good)===1&&<label className="pc-confirm"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)}/>{t('recordingOverproductionConfirm')}</label>}
     <p className="muted">{t(can('orders','approve')?'pcSelfApprovalHelp':'pcPendingHelp')}</p>
     <button className="primary" disabled={!valid||!action.ready}>{t(can('orders','approve')?'pcSaveCorrection':'pcSubmit')}</button>
    </fieldset>
   </form>}
   {action.error&&<p role="alert">{t(action.error)}{action.error==='pcStale'&&<button onClick={read.reload}>{t('pcReload')}</button>}</p>}
   {action.pending&&!action.busy&&<div className="pc-recovery"><p role="status">{t('pcUncertain')}</p><button onClick={()=>void action.recover()}>{t('pcCheckStatus')}</button><button onClick={()=>void action.run('',{})}>{t('pcRetrySame')}</button></div>}
   </>}
  </div>
 </Dialog>;
}
