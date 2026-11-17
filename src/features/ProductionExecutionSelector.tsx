import {useEffect,useRef,useState}from'react';
import {executionCandidate,executionStatus,executionTimeline}from'@/utils/execution-selection.mjs';
import {executionLabels}from'@/utils/execution-labels.mjs';
import {formatTime,localName}from'@/components/ui';
import type{Row}from'@/types';import type{FeatureProps}from'./types';
export default function ProductionExecutionSelector({props,line,orders,selected,complete,loading,error,onReload,onSelect,onBack}:{props:FeatureProps;line:Row;orders:Row[];selected:string;complete:boolean;loading:boolean;error:string;onReload:()=>void;onSelect:(id:string)=>void;onBack:()=>void}){
 const {snapshot:s,t,lang}=props,zone=String(s.factory?.timezone||'Asia/Qatar'),[scale,setScale]=useState(64),[choice,setChoice]=useState(selected),focus=useRef<HTMLHeadingElement>(null),selectedBar=useRef<HTMLButtonElement>(null);
 const candidates=orders.filter(o=>o.line_id===line.id&&executionCandidate(o)),timeline=executionTimeline(candidates,scale),chosen=candidates.find(o=>o.id===choice);
 const [measured,setMeasured]=useState<Record<string,number>>({}),[labelHeight,setLabelHeight]=useState(48),measure=useRef<HTMLDivElement>(null),canvas=useRef<HTMLDivElement>(null),layout=executionLabels(timeline,measured,200,labelHeight),ids=candidates.map(o=>o.id+':'+o.code).join('|');
 useEffect(()=>{const labels=canvas.current?.querySelectorAll<HTMLElement>('[data-label-order]');if(!labels?.length)return;const update=()=>setLabelHeight(Math.max(48,...Array.from(labels,el=>el.getBoundingClientRect().height)));const observer=new ResizeObserver(update);labels.forEach(el=>observer.observe(el));update();return()=>observer.disconnect();},[ids,lang]);
 useEffect(()=>{const node=measure.current;if(!node)return;const update=()=>{const next:Record<string,number>={};node.querySelectorAll<HTMLElement>('[data-measure-order]').forEach(el=>{next[el.dataset.measureOrder!]=el.getBoundingClientRect().width;});setMeasured(old=>JSON.stringify(old)===JSON.stringify(next)?old:next);};const observer=new ResizeObserver(update);node.querySelectorAll('[data-measure-order]').forEach(el=>observer.observe(el));update();return()=>observer.disconnect();},[ids,lang]);
 useEffect(()=>{focus.current?.focus();},[]);
 useEffect(()=>{selectedBar.current?.scrollIntoView({block:'nearest',inline:'center'});},[scale,choice,lang]);
 const time=(v:unknown)=>formatTime(v,lang,zone),unit=(o:Row)=>t(o.unit==='meter'?'meterShort':o.unit==='piece'?'pieceShort':String(o.unit));
 const name=(o:Row)=>{const p=s.tables.products?.find(p=>p.id===o.product_id);return p?localName(p,lang):String((lang==='ar'?o.execution_product_name_ar||o.execution_product_name:o.execution_product_name)||'');};
 return <section className="execution-selector" dir={lang==='ar'?'rtl':'ltr'}>
  <header className="execution-selector-head"><button type="button" onClick={onBack}>{t('executionBackToFloor')}</button><div><h2 tabIndex={-1} ref={focus}>{t('executionSelectOrder')}</h2><p>{localName(line,lang)}</p></div></header>
  <div className="execution-selector-tools"><p>{t('executionTimelineHelp')}</p><label>{t('executionTimelineScale')}<select value={scale} onChange={e=>setScale(Number(e.target.value))}><option value={64}>{t('executionScaleHours')}</option><option value={12}>{t('executionScaleDays')}</option><option value={3}>{t('executionScaleWeeks')}</option></select></label><button type="button" disabled={loading} onClick={onReload}>{t('refresh')}</button></div>
  {loading&&<p role="status">{t('updating')}</p>}{error&&<p role="alert">{t(error)}</p>}
  {complete&&!candidates.length&&<p role="status" className="execution-empty">{t('executionNoUnfinished')}</p>}
  {!!candidates.length&&<>
   <div className="execution-timeline-scroll" role="region" tabIndex={0} aria-label={t('executionOrderTimeline')}>
    <div ref={canvas} className="execution-timeline" style={{width:layout.width,height:layout.height}}>
     <div className="execution-time-axis">{layout.ticks.map((tick:{at:number;left:number})=><time key={tick.at} style={{insetInlineStart:tick.left}} dateTime={new Date(tick.at).toISOString()}>{time(new Date(tick.at).toISOString())}</time>)}</div>
     {layout.slots.map((slot:{order:Row;left:number;width:number;barTop:number;fits:boolean;labelLeft:number;labelTop:number})=>{const o=slot.order,blocker=String(o.execution_start_blocker||''),label=`${o.code} · ${name(o)}`;return <div key={String(o.id)}>
      <button type="button" ref={o.id===choice?selectedBar:undefined} className="execution-time-bar" data-order-id={String(o.id)} data-running={o.status==='active'} data-blocked={Boolean(blocker)} aria-pressed={o.id===choice} aria-label={`${label} · ${time(o.start_time)} — ${time(o.expected_finish)} · ${t(blocker||executionStatus(o))}`} title={label} style={{insetInlineStart:slot.left,width:slot.width,top:slot.barTop}} onClick={()=>setChoice(String(o.id))}>{slot.fits&&<bdi>{String(o.code)}</bdi>}</button>
      <svg className="execution-label-connector" aria-hidden="true" width={layout.width} height={slot.labelTop} style={{transform:lang==='ar'?'scaleX(-1)':undefined}}><path d={`M ${slot.left+slot.width/2} ${slot.barTop+40} L ${slot.labelLeft+8} ${slot.labelTop}`} /></svg><button type="button" className="execution-short-label" data-label-order={String(o.id)} aria-pressed={o.id===choice} title={label} onClick={()=>setChoice(String(o.id))} style={{insetInlineStart:slot.labelLeft,top:slot.labelTop}}><bdi>{String(o.code)}</bdi><span dir="auto">{name(o)}</span></button>
     </div>;})}
     <div ref={measure} className="execution-label-measure" aria-hidden="true">{candidates.map(o=><span key={String(o.id)} data-measure-order={String(o.id)}>{String(o.code)}</span>)}</div>
    </div>
   </div>
   <label className="execution-accessible-choice">{t('executionAccessibleSelection')}<select value={chosen?choice:''} onChange={e=>setChoice(e.target.value)}><option value="" disabled>{t('select')}</option>{timeline.slots.map(({order:o}:{order:Row})=><option key={String(o.id)} value={String(o.id)}>{String(o.code)} · {name(o)} · {time(o.start_time)} · {t(String(o.execution_start_blocker||executionStatus(o)))}</option>)}</select></label>
  </>}
  {chosen&&<section className="execution-selected-details" aria-label={t('executionOrderDetails')} aria-live="polite">
   <header><strong><bdi>{String(chosen.code)}</bdi></strong><span>{t(executionStatus(chosen))}</span></header><h3 dir="auto">{name(chosen)}</h3>
   <p><bdi>{time(chosen.start_time)} — {time(chosen.expected_finish)}</bdi></p>
   <p>{t('recordingRequired')}: <bdi>{String(chosen.target_quantity)} {unit(chosen)}</bdi> · {t('recordingRemaining')}: <bdi>{String(chosen.execution_remaining_quantity)} {unit(chosen)}</bdi></p>
   <p className={chosen.execution_start_blocker?'notice':undefined}>{t(chosen.status==='active'?'f341ActualOrder':String(chosen.execution_start_blocker||'executionChecksAtStart'))}</p>
   {chosen.execution_reason_required===true&&<p>{t('executionPriorityReason')} {t('executionBypassedOrder')}: <bdi>{String((chosen.execution_bypassed_order as {code?:string}|null)?.code||'')}</bdi></p>}
  </section>}
  <footer className="execution-selector-foot"><p>{t(chosen?'executionSelectionOnly':'executionChooseCard')}</p><button type="button" className="primary" disabled={!complete||!chosen} onClick={()=>chosen&&onSelect(String(chosen.id))}>{t('executionUseSelection')}</button></footer>
 </section>;
}
