import {useEffect,useState} from 'react';
import {Dialog,Field,formatTime,localName} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import {historyNumber} from '@/utils/production-history-view.mjs';
import {correctionDifference} from '@/utils/production-correction-ui.mjs';
import {useCorrectionAction,type CorrectionRequest} from './useCorrectionAction';
import type {FeatureProps} from './types';
import type {Row} from '@/types';
import {useTableDetails} from '@/components/useTableDetails';
type Page={rows:CorrectionRequest[];total:number;next_cursor:string|null;metadata?:{items:Row[];requests:Row[];products:Row[]}};
export default function ProductionCorrections(props:FeatureProps&{onChanged?:()=>void}){
 const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''),actor=s.user.id;
 const detailsRow=useTableDetails();
 const [status,setStatus]=useState('PENDING'),[cursor,setCursor]=useState(''),[revision,setRevision]=useState(0),[selection,setSelection]=useState(''),[mode,setMode]=useState(''),[reason,setReason]=useState(''),[notice,setNotice]=useState('');
 const scope=actor+'|'+factory+'|'+status;
 const query=new URLSearchParams({factory,...(status==='mine'?{mine:'1'}:{status}),...(cursor?{cursor}:{})});
 const read=useHistoryData<Page>(can('orders','view')?'/api/production-corrections?'+query:null,String(revision));
 const [loaded,setLoaded]=useState<{scope:string;page:Page}|null>(null);
 useEffect(()=>{if(read.data){const data=read.data;setLoaded(previous=>({scope,page:cursor&&previous?.scope===scope?{...data,rows:[...previous.page.rows,...data.rows.filter(row=>!previous.page.rows.some(old=>old.id===row.id))],metadata:{items:[...(previous.page.metadata?.items||[]),...(data.metadata?.items||[])],requests:[...(previous.page.metadata?.requests||[]),...(data.metadata?.requests||[])],products:[...(previous.page.metadata?.products||[]),...(data.metadata?.products||[])]}}:data}));}},[read.data,scope,cursor]);
 const rows=loaded?.scope===scope?loaded.page.rows:[];
 const selected=rows.find(row=>row.id===selection),page=loaded?.scope===scope?loaded.page:null;
 const approve=can('orders','view')&&can('orders','approve'),stale=selected&&JSON.stringify(selected.original_values)!==JSON.stringify(selected.current_values);
 function refresh(){setCursor('');setLoaded(null);setSelection('');setMode('');setRevision(x=>x+1);}
 const action=useCorrectionAction(actor,factory,row=>{setNotice(row.status==='REJECTED'?'pcRejectedSuccess':row.status==='APPROVED'?'pcApprovedSuccess':'pcPendingSuccess');props.onChanged?.();refresh();void props.refreshSnapshot?.();});
 const quantity=(value:unknown,unit:string)=>`${historyNumber(value,lang)??t('notAvailable')} ${t(unit==='meter'?'meterShort':unit==='piece'?'pieceShort':unit==='kg'?'kg':'legacyUnit')}`;
 const identity=(row:CorrectionRequest)=>{const v=row.current_values;const request=page?.metadata?.requests.find(x=>x.id===v.request_id)||s.tables.production_requests?.find(x=>x.id===v.request_id);const product=page?.metadata?.products.find(x=>x.id===v.product_id)||s.tables.products?.find(x=>x.id===v.product_id);return <><bdi>{String(request?.code||t('notAvailable'))}</bdi><span dir="auto">{product?localName(product,lang):t('notAvailable')}</span></>;};
 const person=(id:string)=>String(s.tables.production_technicians?.find(row=>row.user_id===id)?.display_name||t('notAvailable'));
 const changed=(row:CorrectionRequest,current=false)=>{const v=current||row.status==='PENDING'?row.current_values:row.original_values,p=row.status==='APPROVED'&&row.applied_values?row.applied_values:row.proposed;return <><span>{t('historyGood')}: <bdi>{quantity(v.good,v.unit)}</bdi> {lang==='ar'?'←':'→'} <bdi>{quantity(p.good,v.unit)}</bdi></span><span>{t('historyScrap')}: <bdi>{quantity(v.scrap_kg,'kg')}</bdi> {lang==='ar'?'←':'→'} <bdi>{quantity(p.scrap_kg,'kg')}</bdi></span></>;};
 if(!can('orders','view'))return <p role="alert">{t('permissionError')}</p>;
 return <section className="production-corrections" dir={lang==='ar'?'rtl':'ltr'}>
  <header><h2>{t('productionCorrections')}</h2><p className="muted">{t('pcQueueHelp')}</p></header>
  <div className="pc-toolbar"><Field label={t('status')}><select value={status} onChange={e=>{setStatus(e.target.value);setCursor('');setLoaded(null);setSelection('');setMode('');}}>{['PENDING','APPROVED','REJECTED','mine'].map(key=><option key={key} value={key}>{t('pcStatus_'+key)}</option>)}</select></Field>
   <div className="pc-actions"><button type="button" popoverTarget="pc-actions-menu" disabled={!selected||read.loading||!!read.error||action.busy}>{t('historyActions')} ▾</button><div id="pc-actions-menu" popover="auto" onClick={e=>e.currentTarget.hidePopover()}>
    <button disabled={!selected||read.loading||!!read.error||action.busy} onClick={()=>{setMode('details');setReason('');}}>{t('historyViewDetails')}</button>
    {approve&&selected?.status==='PENDING'&&<><button disabled={read.loading||!!read.error||action.busy} onClick={()=>{setMode('approve');setReason('');}}>{t('approve')}</button><button disabled={read.loading||!!read.error||action.busy} onClick={()=>{setMode('reject');setReason('');}}>{t('reject')}</button></>}
   </div></div><button disabled={action.busy} onClick={refresh}>{t('refresh')}</button>
  </div>
  {notice&&<p role="status">{t(notice)}</p>}{read.loading&&<p role="status">{t('loading')}</p>}
  {read.error&&<p role="alert">{t(read.error)} <button onClick={refresh}>{t('refresh')}</button></p>}
  {status==='mine'&&<p className="muted">{t('pcMyRequestsHelp')}</p>}
  {!read.loading&&!read.error&&!rows.length&&<p>{t('noResults')}</p>}
  <div className="table-wrap"><table><caption className="sr-only">{t('productionCorrections')}</caption><thead><tr>{['pcRequestDate','pcIdentity','pcRequester','pcQuantityChange','pcReason','status'].map(key=><th key={key} scope="col">{t(key)}</th>)}</tr></thead>
   <tbody>{rows.map(row=><tr key={row.id} tabIndex={0} aria-selected={selection===row.id} className={selection===row.id?'pc-selected':''} {...detailsRow(()=>setSelection(row.id),()=>{setMode('details');setReason('');},read.loading||!!read.error||action.busy)}>
    <td data-label={t('pcRequestDate')}>{formatTime(row.requested_at,lang,String(s.factory?.timezone||'UTC'))}</td><td data-label={t('pcIdentity')}>{identity(row)}</td><td data-label={t('pcRequester')}>{person(row.requested_by)}</td><td data-label={t('pcQuantityChange')}>{changed(row)}</td><td dir="auto" data-label={t('pcReason')}>{row.proposed.reason}</td><td data-label={t('status')}>{t('pcStatus_'+row.status)}</td>
   </tr>)}</tbody></table></div>
  {page?.next_cursor&&<button disabled={read.loading||action.busy} onClick={()=>{setCursor(page.next_cursor||'');setSelection('');}}>{t('pcLoadMore')}</button>}
  {action.error&&<p role="alert">{t(action.error)}{action.error==='pcStale'&&<button onClick={refresh}>{t('pcReload')}</button>}</p>}
  {action.pending&&!action.busy&&<div className="pc-recovery"><p>{t('pcUncertain')}</p><button onClick={()=>void action.recover()}>{t('pcCheckStatus')}</button><button onClick={()=>void action.run('',{})}>{t('pcRetrySame')}</button></div>}
  {selected&&mode&&<Dialog title={t(mode==='approve'?'approve':mode==='reject'?'reject':'historyViewDetails')} t={t} busy={action.busy} className="pc-dialog" onClose={()=>{if(!action.busy)setMode('');}}>
   <div className="pc-body" dir={lang==='ar'?'rtl':'ltr'}><header>{identity(selected)}</header><p>{t('pcRequester')}: {person(selected.requested_by)}</p>
    <div className="pc-change">{changed(selected,true)}</div><p>{t('pcDifference')}: <bdi>{quantity(correctionDifference(selected.proposed.good,selected.current_values.good),selected.current_values.unit)}</bdi> · <bdi>{quantity(correctionDifference(selected.proposed.scrap_kg,selected.current_values.scrap_kg),'kg')}</bdi></p>
    <p dir="auto">{t('pcReason')}: {selected.proposed.reason}</p>
    {stale&&<p role="alert">{t('pcStale')}</p>}
    <details><summary>{t('pcSubmissionDetails')}</summary><p>{t('pcOfficialAtRequest')}: <bdi>{quantity(selected.original_values.good,selected.original_values.unit)} · {quantity(selected.original_values.scrap_kg,'kg')}</bdi></p><p>{t('unfinishedQuantity')}: <bdi>{quantity(selected.current_values.unfinished,selected.current_values.unit)} → {quantity(selected.proposed.unfinished,selected.current_values.unit)}</bdi></p>{selected.allocations?.length>0&&<p>{t('sourceSelection')}: {selected.allocations.map((p,i)=><span key={i}><bdi>{p.source_id||t('sourceUnattributed')} · {quantity(p.quantity,selected.current_values.unit)}</bdi></span>)}</p>}</details>
    {selected.rejection_reason&&<p dir="auto">{t('pcRejectionReason')}: {selected.rejection_reason}</p>}
    {selected.status==='PENDING'&&approve&&mode==='details'&&<div className="row-actions"><button disabled={!!stale} onClick={()=>setMode('approve')}>{t('approve')}</button><button onClick={()=>setMode('reject')}>{t('reject')}</button></div>}
    {selected.status==='PENDING'&&approve&&mode!=='details'&&<form onSubmit={e=>{e.preventDefault();if(!approve||action.busy||action.pending||mode==='approve'&&stale)return;void action.run(mode,{id:selected.id,...(mode==='reject'?{reason:reason.trim()}:{})});}}>
     {mode==='reject'&&<Field label={t('pcRejectionReason')}><textarea required minLength={3} maxLength={2000} value={reason} disabled={action.busy||!!action.pending} onChange={e=>setReason(e.target.value)}/></Field>}
     <button className="primary" disabled={action.busy||!!action.pending||!action.ready||mode==='approve'&&!!stale||mode==='reject'&&reason.trim().length<3}>{t(mode==='approve'?'approve':'reject')}</button>
    </form>}
    {action.error&&<p role="alert">{t(action.error)}</p>}
   </div>
  </Dialog>}
 </section>;
}
