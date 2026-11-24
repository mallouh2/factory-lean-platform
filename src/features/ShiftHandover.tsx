import {useEffect,useRef,useState, type FormEvent, type ReactNode} from 'react';
import EntityCombobox from '@/components/EntityCombobox';
import HistoryQueryState from '@/components/HistoryQueryState';
import {formatTime,localName} from '@/components/ui';
import {useHistoryData} from '@/hooks/useHistoryData';
import {decimalSubtract} from '@/utils/quality-quantities.mjs';
import {compareHandoverCount,handoverCountValid,roundHandoverKg} from '@/utils/shift-handover-counts.mjs';
import type {FeatureProps} from './types';
import type {Count,Note,Work} from './ProductionStock';
import type {useProductionStockCommand} from './useProductionStockCommand';
import styles from './ShiftHandover.module.css';

type Occurrence = NonNullable<Work['occurrence']['occurrence']>;
type Goods = {id:string;item_id:string;code:string;product:string;product_ar?:string;
  line:string;line_ar?:string;unit:string;quality:string;warehouse:string;expected:string;actual?:string;
  difference?:string;significant?:boolean};
type Receipt = {raw:Count[];goods:Goods[];occurrence:Occurrence;note:string};
type Exchange = {id:string;occurrence:Occurrence;raw:Count[];goods:Goods[];notes:Note[];note:string;
  deviation_percent:string;submitted_at:string;submitted_by:string;submitter_id:string;
  received_at?:string;received_by?:string;receipt?:Receipt};
type ExchangeWork = {goods:Goods[];goods_revision:string;occurrence:Work['occurrence'];raw_precision?:'whole_kg';
  current:Exchange|null;pending:Exchange[];history:Exchange[];history_total:number};
type Order = {id:string;code:string;status:string;product:string;product_ar?:string;line?:string;line_ar?:string};
type Action = ReturnType<typeof useProductionStockCommand>;
type CountRow = {id:string;expected:string;unit:string;actual?:string;difference?:string;
  significant?:boolean;outgoing?:string;outgoingDifference?:string;outgoingSignificant?:boolean;label:string;cells:ReactNode[]};
type CountState = {raw:Record<string,string>;goods:Record<string,string>;note:string};
const empty:CountState = {raw:{},goods:{},note:''};
const compactQuantity = (value:string) => decimalSubtract(value,'0')??value;
const quantityText=(value:string,wholeKg:boolean)=>wholeKg?roundHandoverKg(value):compactQuantity(value);

function Counts({rows,headers,values,onChange,threshold,t,kind,incoming,showReceipt,wholeKg=false}:{
  rows:CountRow[];headers:string[];values?:Record<string,string>;onChange?:(id:string,value:string)=>void;
  threshold:string;t:FeatureProps['t'];kind:'raw'|'goods';incoming:boolean;showReceipt:boolean;wholeKg?:boolean;
}){
  if(!rows.length)return <p className={styles.empty}>{t(kind==='raw'?'handoverNoRaw':'handoverNoGoods')}</p>;
  const actualLabel=t(showReceipt||incoming?'handoverIncomingCount':'psActualCount');
  const columns=[...headers,t('handoverSystemQuantity'),...(incoming||showReceipt?[t('handoverOutgoingCount')]:[]),
    actualLabel,t('psDifference')];
  return <table className={styles.table} data-kind={kind} role="table">
    <thead><tr>{columns.map((column,index)=><th scope="col" key={index}>{column}</th>)}</tr></thead>
    <tbody>{rows.map(row=>{
      const baseline=incoming||showReceipt?(row.outgoing||row.expected):row.expected;
      const comparison=compareHandoverCount(onChange?values?.[row.id]:row.actual&&quantityText(row.actual,wholeKg),baseline,threshold,wholeKg);
      const difference=onChange?comparison:{difference:wholeKg?comparison.difference:row.difference,significant:row.significant};
      const quantity=(value:string|undefined,delta=false)=>value===undefined?'—':<bdi>
        {delta?compactQuantity(value):quantityText(value,wholeKg)} {t(row.unit)}</bdi>;
      const incomplete=Boolean(onChange&&!handoverCountValid(values?.[row.id],wholeKg));
      const outgoingDelta=wholeKg&&row.outgoing!==undefined
        ?decimalSubtract(roundHandoverKg(row.outgoing),roundHandoverKg(row.expected))
        :row.outgoingDifference;
      return <tr key={row.id} data-discrepancy={Boolean(difference.significant||row.outgoingSignificant)}>
        {row.cells.map((cell,index)=><td data-label={headers[index]} key={index}>{cell}</td>)}
        <td data-label={t('handoverSystemQuantity')}>{quantity(row.expected)}</td>
        {(incoming||showReceipt)&&<td data-label={t('handoverOutgoingCount')}>{quantity(row.outgoing)}
          {row.outgoingSignificant&&<small className={styles.warning}>{outgoingDelta==='0'?t('handoverRecordedDiscrepancy')
            :<>{t('psDifference')} {quantity(outgoingDelta??undefined,true)}</>}</small>}</td>}
        <td data-label={actualLabel}>{onChange
          ? <input aria-label={actualLabel+' · '+row.label}
            aria-invalid={incomplete} aria-describedby={incomplete?'handover-incomplete-counts':undefined}
            inputMode={wholeKg?'numeric':'decimal'} dir="ltr" value={values?.[row.id]??''}
            placeholder={t('handoverCountRequired')} maxLength={wholeKg?24:37}
            onChange={event=>onChange(row.id,event.target.value.replace(/[\u0660-\u0669\u06f0-\u06f9]/g,
              digit=>String(digit.charCodeAt(0)%16)).replace(/\u066b|,/g,'.'))}/>
          : quantity(row.actual)}</td>
        <td data-label={t('psDifference')}><span className={difference.significant?styles.warning:undefined}>
          {quantity(difference.difference??undefined,true)}
          {difference.significant&&<small>{t(difference.difference==='0'?'handoverRecordedDiscrepancy':'handoverDiscrepancy')}</small>}
        </span></td>
      </tr>;
    })}</tbody>
  </table>;
}

export default function ShiftHandover({props,work,action,changed,refreshWork,notesPage,setNotesPage,handoverPage,setHandoverPage}:{
  props:FeatureProps;work:Work;action:Action;changed:()=>void;refreshWork:()=>void;notesPage:number;
  setNotesPage:(page:number)=>void;handoverPage:number;setHandoverPage:(page:number)=>void;
}){
  const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||''), actor=s.user.id;
  const [history,setHistory]=useState(false),[target,setTarget]=useState('');
  const [edited,setEdited]=useState({key:'',counts:empty});
  const [archived,setArchived]=useState(false);
  const [baseline,setBaseline]=useState<{work:Work;exchange:ExchangeWork}|null>(null);
  const [message,setMessage]=useState(''),[showNote,setShowNote]=useState(false);
  const editor=useRef<HTMLDivElement>(null);
  const root='/api/production-stock?';
  const requestUrl=(params:Record<string,string>)=>root+new URLSearchParams({factory,...params});
  const url=requestUrl({mode:'handover',page:String(history?handoverPage:1)});
  const query=useHistoryData<{data:ExchangeWork}>(url,s.fetchedAt,url,true);
  const server=query.data?.data;
  const detailUrl=target&&target!=='new'?requestUrl({mode:'handover',target}):null;
  const detailQuery=useHistoryData<{data:{selection:Exchange|null}}>(detailUrl,s.fetchedAt,detailUrl,true);
  const exchange=baseline?.exchange||server;
  const list=server?[...new Map([...server.pending,...(server.current?[server.current]:[])].map(row=>[row.id,row])).values()]:[];
  const detail=target==='new'?undefined:target?list.find(row=>row.id===target)||detailQuery.data?.data.selection||undefined
    :list.find(row=>!row.receipt&&row.submitter_id!==actor)||server?.current||list[0];
  const occurrence=server?.occurrence.occurrence;
  const accessReason=!work.enabled?'production_stock_disabled'
    :!can('orders','view')||!can('orders','edit')?'handoverNeedsPermission'
    :!occurrence?'recording_shift_unavailable':'';
  const prepareReason=accessReason||(server?.current?'handoverCurrentSubmitted':'');
  const receivable=list.find(row=>!row.receipt&&row.submitter_id!==actor);
  const receiptReason=accessReason||(!receivable
    ?list.some(row=>!row.receipt&&row.submitter_id===actor)?'handover_requires_incoming':'handoverNoIncoming'
    :'');
  const incoming=Boolean(!receiptReason&&!archived&&detail&&!detail.receipt&&detail.submitter_id!==actor);
  const draftKey=incoming?detail?.id+'|'+occurrence?.occurrence_key:'outgoing';
  const draft=edited.key===draftKey?edited.counts:empty;
  const editDraft=(update:(previous:CountState)=>CountState)=>{
    setEdited(previous=>({key:draftKey,counts:update(previous.key===draftKey?previous.counts:empty)}));
  };
  const preparing=Boolean(server&&!archived&&!detail&&!detailUrl&&!prepareReason);
  const counting=preparing||incoming;
  const wholeKg=server?.raw_precision==='whole_kg';
  const activeWork=baseline?.work||work;
  const threshold=String(detail?.deviation_percent??activeWork.deviation_percent??'0');
  const lines=s.tables.production_lines||[],machines=s.tables.work_centers||[],members=s.tables.memberships||[];
  const displayName=(id:string)=>String((id===actor?s.membership?.display_name:null)||
    members.find(m=>m.user_id===id)?.display_name||t('notAvailable'));
  const when=(date:string)=>formatTime(date,lang,String(s.factory?.timezone||'UTC'));
  const shiftName=(row:Occurrence)=>lang==='ar'?row.name_ar||row.name:row.name;
  const currentTech=displayName(actor);
  const noteSource=detail?.notes||work.notes.filter(n=>n.occurrence?.occurrence_key===occurrence?.occurrence_key);
  const followUps=work.notes.filter(n=>n.follow_up&&!n.resolved);
  const allNotes=archived||detail?.receipt?noteSource:[...new Map([...followUps,...noteSource.map(n=>({...n,...work.notes.find(value=>value.id===n.id)}))]
    .map(n=>[n.id,n])).values()];
  const rawRows:CountRow[]=detail?detail.raw.map(row=>{
    const receipt=detail.receipt?.raw.find(r=>r.material===row.material);
    const label=localName(activeWork.stocks.find(s=>s.id===row.material),lang)||row.name;
    return {id:row.material,label,unit:row.unit,expected:row.expected,
      actual:receipt?.actual??row.actual,outgoing:row.actual,outgoingDifference:row.difference,outgoingSignificant:row.significant,
      difference:receipt?.difference??row.difference,
      significant:receipt?.significant??row.significant,cells:[<strong>{label}</strong>,
        <bdi>{quantityText(row.reserved,wholeKg)} {t(row.unit)}</bdi>,<bdi>{quantityText(row.unreserved,wholeKg)} {t(row.unit)}</bdi>]};
  }):activeWork.stocks.map(row=>({id:row.id,label:localName(row,lang),unit:row.unit,expected:row.physical,
    cells:[<strong>{localName(row,lang)}</strong>,<bdi>{quantityText(row.reserved,wholeKg)} {t(row.unit)}</bdi>,
      <bdi>{quantityText(row.available,wholeKg)} {t(row.unit)}</bdi>]}));
  const goodsRows:CountRow[]=(detail?.goods||exchange?.goods||[]).map(row=>{
    const receipt=detail?.receipt?.goods.find(g=>g.id===row.id);
    const product=lang==='ar'?row.product_ar||row.product:row.product;
    const line=lang==='ar'?row.line_ar||row.line:row.line;
    const quality=t('handover_'+row.quality);
    return {id:row.id,label:[row.code,product,quality].join(' · '),unit:row.unit,expected:row.expected,
      outgoing:row.actual,outgoingDifference:row.difference,outgoingSignificant:row.significant,
      actual:receipt?.actual??row.actual,difference:receipt?.difference??row.difference,
      significant:receipt?.significant??row.significant,
      cells:[<><strong><bdi>{row.code}</bdi></strong><small>{product}</small><small>{line||t('notAvailable')}</small></>,
        <span className={row.quality==='approved'||row.quality==='legacy_finished'?styles.approved:styles.badge}>{quality}</span>,
        <span className={styles.badge}>{t('handover_'+row.warehouse)}</span>]};
  });
  const countValues=(rows:CountRow[],overrides:Record<string,string>,whole=false)=>Object.fromEntries(rows.map(row=>[
    row.id,overrides[row.id]??(incoming&&row.outgoing!==undefined?quantityText(row.outgoing,whole):'')??'',
  ]));
  const rawValues=countValues(rawRows,draft.raw,wholeKg);
  const goodsValues=countValues(goodsRows,draft.goods);
  const discrepancies=(rows:CountRow[],values:Record<string,string>,limit:string,whole=false)=>
    rows.filter(row=>compareHandoverCount(values[row.id],incoming?(row.outgoing??row.expected):row.expected,limit,whole).significant).length;
  const countProblems=discrepancies(rawRows,rawValues,threshold,wholeKg)+discrepancies(goodsRows,goodsValues,'0');
  const remaining=rawRows.filter(row=>!handoverCountValid(rawValues[row.id],wholeKg)).length+
    goodsRows.filter(row=>!handoverCountValid(goodsValues[row.id])).length;
  const complete=remaining===0;
  const locked=action.busy||Boolean(action.pending)||!action.ready;
  const reset=()=>{setEdited({key:'',counts:empty});setBaseline(null);setShowNote(false);setMessage('');};
  const inspect=(id:string,readOnly=false)=>{reset();setTarget(id);setHistory(false);setArchived(readOnly);};
  const changeCount=(group:'raw'|'goods',id:string,value:string)=>{
    if(!baseline&&!detail&&server)setBaseline({work,exchange:server});
    editDraft(current=>({...current,[group]:{...current[group],[id]:value}}));
  };
  function refresh(){
    query.reload();detailQuery.reload();refreshWork();
  }
  async function submit(){
    if(!counting||locked||message||!occurrence||!complete||countProblems>0&&draft.note.trim().length<3)return;
    const raw=rawRows.map(row=>({id:row.id,quantity:rawValues[row.id]}));
    const goods=goodsRows.map(row=>({id:row.id,quantity:goodsValues[row.id]}));
    const counted={raw,goods,note:draft.note,occurrence_key:(exchange?.occurrence.occurrence||occurrence).occurrence_key};
    const result=incoming
      ? await action.run('HANDOVER_RECEIVE',{...counted,handover_id:detail?.id})
      : await action.run('HANDOVER_SUBMIT',{...counted,stock_revision:activeWork.stock_revision,goods_revision:exchange?.goods_revision});
    if(result){
      inspect(String(result.id));
      setMessage(t(incoming?'handoverReceivedMessage':'handoverSubmittedMessage'));
      refresh();
    }
  }
  const status=(row:Exchange)=>t(row.receipt?'handoverReceived':'handoverAwaiting');
  const historyRows=server?.history||[];
  const prior=work.handovers.filter(row=>!historyRows.some(exchange=>exchange.id===row.id)&&
    !list.some(exchange=>exchange.id===row.id));
  const [legacyId,setLegacyId]=useState('');
  const legacy=prior.find(row=>row.id===legacyId);
  const historicalLegacy=legacy&&history;
  const sectionNotes=(kind:'equipment'|'order')=><NotesSection {...{
    props,work,action,changed,root,kind,editable:preparing,
    allowFollowUp:!accessReason&&!archived&&!detail?.receipt,notes:allNotes.filter(n=>kind==='order'?Boolean(n.item_id):!n.item_id),
    displayName,when,
  }}/>;
  const archivedNotes=work.notes.filter(note=>Boolean(note.occurrence?.occurrence_key)&&
    note.occurrence?.occurrence_key!==occurrence?.occurrence_key);
  return <div className={styles.workspace} ref={editor}>
    <div className={styles.topbar}>
      <div><h3>{t(history?'psHandoverHistory':'psTab_handover')}</h3>
        {!history&&occurrence&&<p>{shiftName(occurrence)} · {when(occurrence.starts_at)} · {currentTech}</p>}</div>
      <button type="button" onClick={()=>{if(history||archived)inspect('');else setHistory(true);setLegacyId('')}}>
        {t(history||archived?'handoverBackToCurrent':'psHandoverHistory')}
      </button>
    </div>
    <HistoryQueryState {...query} t={t}/>
    {message&&<p role="status">{message}</p>}
    {history?<div className={styles.history}>
      {!historyRows.length&&!prior.length&&<p className={styles.empty}>{t('handoverNoHistory')}</p>}
      {historyRows.map(row=><button type="button" key={row.id} onClick={()=>inspect(row.id,true)}>
        <strong>{shiftName(row.occurrence)}</strong> · {when(row.submitted_at)} · {row.submitted_by} · {status(row)}
      </button>)}
      {prior.map(row=><button type="button" key={row.id} aria-pressed={legacyId===row.id} onClick={()=>setLegacyId(row.id)}>
        {when(row.created_at)} · {displayName(row.actor)} · {t('handoverLegacy')}
      </button>)}
      {historicalLegacy&&<><Counts rows={legacy.counts.map(row=>({...row,id:row.material,label:row.name,cells:[
        <strong>{row.name}</strong>,<bdi>{quantityText(row.reserved,wholeKg)} {t(row.unit)}</bdi>,
        <bdi>{quantityText(row.unreserved,wholeKg)} {t(row.unit)}</bdi>]}))}
        headers={[t('rawReturnMaterial'),t('psReserved'),t('psUnreserved')]} threshold={threshold} {...{t}}
        kind="raw" incoming={false} showReceipt={false} wholeKg={wholeKg}/>{legacy.note&&<p dir="auto">{legacy.note}</p>}</>}
      <div className="row-actions">
        <button disabled={handoverPage<=1} onClick={()=>{setHandoverPage(handoverPage-1);setLegacyId('')}}>{t('previous')}</button>
        <span>{handoverPage}</span>
        <button disabled={handoverPage*20>=(server?.history_total||0)&&handoverPage*30>=work.handovers_total}
          onClick={()=>{setHandoverPage(handoverPage+1);setLegacyId('')}}>{t('next')}</button>
      </div>
      {archivedNotes.length>0&&<details>
        <summary>{t('psShiftNotes')}</summary>
        {(['equipment','order'] as const).map(kind=><NotesSection key={kind} {...{
          props,work,action,changed,root,kind,editable:false,allowFollowUp:false,displayName,when,
          notes:archivedNotes.filter(note=>kind==='order'?Boolean(note.item_id):!note.item_id),
        }}/>)}
        <div className="row-actions">
          <button disabled={notesPage<=1} onClick={()=>setNotesPage(notesPage-1)}>{t('previous')}</button>
          <span>{notesPage}</span>
          <button disabled={notesPage*50>=work.notes_total} onClick={()=>setNotesPage(notesPage+1)}>{t('next')}</button>
        </div>
      </details>}
    </div>:server&&<>
      {!archived&&<div className={styles.workflowActions}>
        <div><button type="button" aria-pressed={preparing} aria-describedby={prepareReason?'handover-prepare-reason':undefined}
          disabled={locked||Boolean(prepareReason)} onClick={()=>{if(!preparing)inspect('new')}}>{t('handoverPrepare')}</button>
          {prepareReason&&<small id="handover-prepare-reason">{t(prepareReason)}</small>}</div>
        <div><button type="button" aria-pressed={incoming} aria-describedby={receiptReason?'handover-receipt-reason':undefined}
          disabled={locked||Boolean(receiptReason)} onClick={()=>{if(receivable&&!incoming)inspect(receivable.id)}}>{t('handoverReviewReceipt')}</button>
          {receiptReason&&<small id="handover-receipt-reason">{t(receiptReason)}</small>}</div>
      </div>}
      {!archived&&list.length>1&&
        <label className={styles.selection}>{t('handoverSelect')}
          <select value={detail?.id||(target==='new'?'new':target)} onChange={event=>inspect(event.target.value)}>
            {!server.current&&<option value="new">{t('handoverNew')}</option>}
            {detail&&!list.some(row=>row.id===detail.id)&&<option value={detail.id}>{shiftName(detail.occurrence)} · {status(detail)}</option>}
            {list.map(row=><option key={row.id} value={row.id}>{shiftName(row.occurrence)} · {when(row.submitted_at)} · {status(row)}</option>)}
          </select>
        </label>}
      {detailUrl&&!detail&&<HistoryQueryState {...detailQuery} t={t}/>}
      {(!detailUrl||detail)&&<>
        <div className={styles.state} data-received={Boolean(detail?.receipt)}>
          <strong>{detail?status(detail):t('handoverPending')}</strong>
          {detail&&<span>{shiftName(detail.occurrence)} · {t('handoverSubmittedBy')} {detail.submitted_by||t('notAvailable')} · {when(detail.submitted_at)}</span>}
          {detail?.received_at&&<span>{t('handoverReceivedBy')} {detail.received_by||t('notAvailable')} · {when(detail.received_at)}</span>}
          {(archived||detail?.receipt)&&<span>{t('handoverReadOnly')}</span>}
          {incoming&&!receiptReason&&<span>{t('handoverVerifyTip')}</span>}
        </div>
        <section className={styles.section} aria-label={t('handoverRaw')}>
          <header><h4>{t('handoverRaw')}</h4>{!detail&&baseline&&<button type="button" disabled={locked}
            onClick={()=>{reset();refresh()}}>{t('handoverRefreshCounts')}</button>}</header>
          {wholeKg&&<p className={styles.empty}>{t('handoverApproximateKg')}</p>}
          <Counts rows={rawRows} headers={[t('rawReturnMaterial'),t('psReserved'),t('psUnreserved')]}
            values={rawValues} onChange={counting&&!locked?(id,value)=>changeCount('raw',id,value):undefined}
            {...{threshold,t,incoming,wholeKg}} kind="raw" showReceipt={Boolean(detail?.receipt)}/>
        </section>
        <section className={styles.section} aria-label={t('handoverGoods')}>
          <header><h4>{t('handoverGoods')}</h4></header>
          <Counts rows={goodsRows} headers={[t('productionOrder'),t('quality'),t('handoverWarehouse')]}
            values={goodsValues} onChange={counting&&!locked?(id,value)=>changeCount('goods',id,value):undefined}
            threshold="0" {...{t,incoming}} kind="goods" showReceipt={Boolean(detail?.receipt)}/>
        </section>
        {sectionNotes('equipment')}
        {sectionNotes('order')}
        {work.notes_total>50&&<div className="row-actions">
          <button disabled={notesPage<=1} onClick={()=>setNotesPage(notesPage-1)}>{t('previous')}</button>
          <span>{t('psShiftNotes')} · {notesPage}</span>
          <button disabled={notesPage*50>=work.notes_total} onClick={()=>setNotesPage(notesPage+1)}>{t('next')}</button>
        </div>}
        {detail?.note&&<p dir="auto"><strong>{t('handoverOutgoingNote')}: </strong>{detail.note}</p>}
        {detail?.receipt?.note&&<p dir="auto"><strong>{t('handoverIncomingNote')}: </strong>{detail.receipt.note}</p>}
        {counting&&<div className={styles.actions}>
          {countProblems>0||showNote?<label>{countProblems>0?t('psInvestigation'):t('notes')}
            <textarea maxLength={2000} value={draft.note} disabled={locked}
              onChange={e=>editDraft(current=>({...current,note:e.target.value}))}/></label>
            :<button type="button" onClick={()=>setShowNote(true)}>{t('handoverAddInvestigation')}</button>}
          {!complete&&<small id="handover-incomplete-counts" role="status">
            {t(incoming?'handoverCompleteReceiptCounts':'handoverCompleteCounts')}{' '}
            {t('handoverRemainingRows').replace('{count}',remaining.toLocaleString(lang))}
          </small>}
          <button className="primary" type="button" disabled={locked||Boolean(message)||!complete||countProblems>0&&draft.note.trim().length<3}
            onClick={()=>void submit()}>{t(incoming?'handoverConfirmReceipt':'handoverSubmit')}</button>
        </div>}
      </>}
    </>}
  </div>;
}

function NotesSection({props,work,action,changed,root,kind,editable,allowFollowUp,notes,displayName,when}:{
  props:FeatureProps;work:Work;action:Action;changed:()=>void;root:string;kind:'equipment'|'order';
  editable:boolean;allowFollowUp:boolean;notes:Note[];displayName:(id:string)=>string;when:(date:string)=>string;
}){
  const {snapshot:s,t,lang,can}=props,factory=String(s.factory?.id||'');
  const [add,setAdd]=useState(false),[reference,setReference]=useState(''),[body,setBody]=useState(''),
    [followUp,setFollowUp]=useState(false),[maintenance,setMaintenance]=useState(''),
    [text,setText]=useState(''),[search,setSearch]=useState(''),[resolve,setResolve]=useState(''),
    [resolution,setResolution]=useState('');
  const [selectedOrder,setSelectedOrder]=useState<Order>();
  useEffect(()=>{const timer=setTimeout(()=>setSearch(text),250);return()=>clearTimeout(timer);},[text]);
  const orderUrl=add&&kind==='order'?root+new URLSearchParams({factory,mode:'handover-orders',search,
    ...(reference?{target:reference}:{})}):null;
  const returned=useHistoryData<{data:{orders:Order[]}}>(orderUrl,'');
  const [targetType,targetId]=reference.split(':');
  const maintenanceUrl=add&&editable&&kind==='equipment'&&can('maintenance','view')&&targetId
    ?root+new URLSearchParams({factory,mode:'handover-maintenance',[targetType]:targetId}):null;
  const applicable=useHistoryData<{data:{id:string;label:string}[]}>(maintenanceUrl,s.fetchedAt,maintenanceUrl,true);
  const maintenanceChoices=applicable.data?.data||[];
  const validMaintenance=maintenanceChoices.some(row=>row.id===maintenance)?maintenance:'';
  const lines=s.tables.production_lines||[],machines=s.tables.work_centers||[];
  const matches=returned.data?.data.orders||[];
  const orders=selectedOrder&&reference===selectedOrder.id&&!matches.some(order=>order.id===reference)
    ? [selectedOrder,...matches]:matches;
  const options=kind==='order'?orders.map(order=>({id:order.id,label:[order.code,
    lang==='ar'?order.product_ar||order.product:order.product,
    lang==='ar'?order.line_ar||order.line:order.line,t(order.status)].filter(Boolean).join(' · ')}))
    :[...lines.filter(row=>!row.archived).map(row=>({id:'line:'+String(row.id),label:localName(row,lang)})),
      ...machines.filter(row=>!row.archived).map(row=>({id:'machine:'+String(row.id),
        label:[localName(row,lang),localName(lines.find(l=>l.id===row.line_id),lang),t(String(row.status))].filter(Boolean).join(' · ')}))];
  const locked=action.busy||Boolean(action.pending)||!action.ready;
  async function submit(event:FormEvent){
    event.preventDefault();
    if(!reference||!body.trim()||locked)return;
    const [type,id]=kind==='order'?['item',reference]:reference.split(':');
    if(await action.run('NOTE',{[type]:id,body:body.trim(),follow_up:followUp,...(validMaintenance?{maintenance:validMaintenance}:{})})){
      setBody('');setFollowUp(false);setMaintenance('');changed();
    }
  }
  function title(note:Note){
    if(note.item_id){
      return String((s.tables.production_orders||[]).find(row=>row.id===note.item_id)?.code||
        orders.find(row=>row.id===note.item_id)?.code||note.item_code||t('productionOrder'));
    }
    const machine=machines.find(row=>row.id===note.machine_id);
    const line=lines.find(row=>row.id===(note.line_id||machine?.line_id));
    return [localName(machine,lang)||note.machine_name,localName(line,lang)||note.line_name,
      machine?t(String(machine.status)):''].filter(Boolean).join(' · ')||(note.machine_id||note.line_id?t('notAvailable'):t('handoverGeneralNote'));
  }
  return <section className={styles.section}>
    <header><h4>{t(kind==='order'?'handoverOrderNotes':'handoverEquipmentNotes')}</h4>
      {editable&&<button type="button" disabled={locked} onClick={()=>setAdd(value=>!value)}>{t(add?'close':'psAddNote')}</button>}</header>
    {add&&editable&&<form className={styles.noteForm} onSubmit={submit}>
      <EntityCombobox label={t(kind==='order'?'productionOrder':'handoverEquipmentTarget')}
        placeholder={t('select')} options={options} value={reference} onChange={id=>{
          setReference(id);
          if(kind==='equipment')setMaintenance('');
          if(kind==='order'&&id)setSelectedOrder(orders.find(order=>order.id===id));
        }}
        onSearch={kind==='order'?setText:undefined} disabled={locked}/>
      {returned.error&&kind==='order'&&<p role="alert">{t(returned.error)}</p>}
      <label>{t('notes')}<textarea rows={2} maxLength={2000} required value={body} disabled={locked} onChange={e=>setBody(e.target.value)}/></label>
      <div className={styles.noteActions}>
        <label><input type="checkbox" checked={followUp} disabled={locked} onChange={e=>setFollowUp(e.target.checked)}/>{t('psNeedsFollowUp')}</label>
        {maintenanceChoices.length>0&&
          <EntityCombobox label={t('psMaintenanceLink')} placeholder={t('select')} options={maintenanceChoices} value={validMaintenance}
            onChange={setMaintenance} disabled={locked}/>}
        {applicable.error&&<small role="status">{t(applicable.error)}</small>}
        <button type="submit" disabled={locked||!reference||!body.trim()}>{t('save')}</button>
      </div>
    </form>}
    {!notes.length&&<p className={styles.empty}>{t('handoverNoNotes')}</p>}
    {notes.map(note=>{
      const events=note.acknowledgments||[];
      const resolutionEvent=events.find(event=>event.operation==='RESOLVE');
      return <article key={note.id} className={styles.note}>
        <div><strong dir="auto">{title(note)}</strong>
          {note.follow_up&&<span className={note.resolved?styles.approved:styles.warning}>{t(note.resolved?'psResolved':'psNeedsFollowUp')}</span>}
        </div>
        <p dir="auto">{note.body}</p>
        <small>{note.author||displayName(note.actor)} · {when(note.created_at)}</small>
        {note.maintenance_request_id&&can('maintenance','view')&&<button type="button" className={styles.contextLink}
          onClick={()=>props.onMaintenanceRepairOpen?.(String(note.maintenance_request_id))}>
          {work.maintenance_choices.find(row=>row.id===note.maintenance_request_id)?.label||t('psMaintenanceLink')}
        </button>}
        {resolutionEvent&&<p dir="auto">{t('psResolved')} · {displayName(resolutionEvent.actor)} · {when(resolutionEvent.created_at)} · {resolutionEvent.body}</p>}
        {allowFollowUp&&note.follow_up&&!note.resolved&&events.some(event=>event.actor===s.user.id&&event.operation==='ACK')&&
          <small>{t('psAcknowledged')}</small>}
        {allowFollowUp&&note.follow_up&&!note.resolved&&!events.some(event=>event.actor===s.user.id&&event.operation==='ACK')&&
          <button type="button" disabled={locked} onClick={async()=>{if(await action.run('ACK',{id:note.id}))changed()}}>
            {t('psAcknowledge')}
          </button>}
        {allowFollowUp&&note.follow_up&&!note.resolved&&resolve!==note.id&&
          <button type="button" disabled={locked} onClick={()=>{setResolve(note.id);setResolution('')}}>{t('psResolve')}</button>}
        {resolve===note.id&&!note.resolved&&<form className={styles.resolve}
          onSubmit={async event=>{event.preventDefault();if(await action.run('RESOLVE',{id:note.id,note:resolution})){setResolve('');changed();}}}>
          <label>{t('psResolution')}<textarea required minLength={3} maxLength={2000} value={resolution} onChange={e=>setResolution(e.target.value)}/></label>
          <button type="submit" disabled={locked||resolution.trim().length<3}>{t('save')}</button>
          <button type="button" onClick={()=>setResolve('')}>{t('cancel')}</button>
        </form>}
      </article>;
    })}
  </section>;
}
