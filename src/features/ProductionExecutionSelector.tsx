import {useEffect,useRef,useState,type CSSProperties}from'react';
import {executionCandidate,executionStatus,executionTimeline}from'@/utils/execution-selection.mjs';
import MeasuredGanttCode from '@/components/MeasuredGanttCode';
import {formatTime,localName}from'@/components/ui';
import type{Row}from'@/types';import type{FeatureProps}from'./types';
export default function ProductionExecutionSelector({props,line,orders,selected,complete,loading,error,onReload,onSelect,onBack}:{props:FeatureProps;line:Row;orders:Row[];selected:string;complete:boolean;loading:boolean;error:string;onReload:()=>void;onSelect:(id:string)=>void;onBack:()=>void}){
 const {snapshot:s,t,lang}=props,zone=String(s.factory?.timezone||'Asia/Qatar'),[scale,setScale]=useState(256),[choice,setChoice]=useState(selected),focus=useRef<HTMLHeadingElement>(null),selectedBar=useRef<HTMLButtonElement>(null);
 const candidates=orders.filter(o=>o.line_id===line.id&&executionCandidate(o)),timeline=executionTimeline(candidates,scale),chosen=candidates.find(o=>o.id===choice);
 const [pointed,setPointed]=useState(''),[focused,setFocused]=useState('');
 const preview=candidates.find(o=>o.id===(pointed||focused))||chosen;
 useEffect(()=>{focus.current?.focus();},[]);
 useEffect(()=>{selectedBar.current?.scrollIntoView({block:'nearest',inline:'center'});},[scale,choice,lang]);
 const time=(v:unknown)=>formatTime(v,lang,zone),unit=(o:Row)=>t(o.unit==='meter'?'meterShort':o.unit==='piece'?'pieceShort':String(o.unit));
 const name=(o:Row)=>{const p=s.tables.products?.find(p=>p.id===o.product_id);return p?localName(p,lang):String((lang==='ar'?o.execution_product_name_ar||o.execution_product_name:o.execution_product_name)||'');};
 const interval=(o:Row)=>time(o.start_time)+' — '+time(o.expected_finish);
 const barStatus=(o:Row)=>t(String(o.execution_start_blocker||executionStatus(o)));
 const ticks=new Intl.DateTimeFormat(lang,{timeZone:zone,month:'short',day:'numeric',...(scale>=64?{hour:'2-digit',minute:'2-digit'}:{})});
 return <section className="execution-selector" dir={lang==='ar'?'rtl':'ltr'}>
  <header className="execution-selector-head"><button type="button" onClick={onBack}>{t('executionBackToFloor')}</button><div><h2 tabIndex={-1} ref={focus}>{t('executionSelectOrder')}</h2><p>{localName(line,lang)}</p></div></header>
  <div className="execution-selector-tools"><p>{t('executionTimelineHelp')}</p><label>{t('executionTimelineScale')}<select aria-label={t('executionTimelineScale')} value={scale} onChange={e=>setScale(Number(e.target.value))}><option value={256}>{t('executionScaleHoursDetail')}</option><option value={64}>{t('executionScaleHours')}</option><option value={12}>{t('executionScaleDays')}</option><option value={3}>{t('executionScaleWeeks')}</option></select></label><button type="button" disabled={loading} onClick={onReload}>{t('refresh')}</button></div>
  {loading&&<p role="status">{t('updating')}</p>}{error&&<p role="alert">{t(error)}</p>}
  {complete&&!candidates.length&&<p role="status" className="execution-empty">{t('executionNoUnfinished')}</p>}
  {!!candidates.length&&<>
   <div className="execution-chart">
    <div className="execution-timeline-scroll" role="region" tabIndex={0} aria-label={t('executionOrderTimeline')}>
     <div className="execution-timeline" style={{inlineSize:timeline.width,'--execution-tick':timeline.tickWidth+'px'} as CSSProperties}>
      <div className="execution-time-axis">
       {timeline.ticks.map(tick=><time key={tick.at}
        style={{insetInlineStart:tick.left,inlineSize:Math.min(timeline.tickWidth,timeline.width-tick.left)}}
        dateTime={new Date(tick.at).toISOString()}>{ticks.format(tick.at)}</time>)}
      </div>
      <div className="execution-track" style={{blockSize:timeline.tracks*32+8}}>
       {timeline.slots.map((slot:{order:Row;left:number;width:number;row:number})=>{
        const o=slot.order,id=String(o.id),label=[String(o.code),name(o),interval(o),barStatus(o)].filter(Boolean).join(' · ');
        return <button key={id} type="button" ref={o.id===choice?selectedBar:undefined} className="execution-time-bar"
         data-order-id={id} data-running={o.status==='active'} data-blocked={Boolean(o.execution_start_blocker)}
         aria-pressed={o.id===choice} aria-label={label} title={label}
         style={{insetInlineStart:slot.left,inlineSize:slot.width,insetBlockStart:slot.row*32+8}}
         onPointerEnter={event=>{if(event.pointerType==='mouse')setPointed(id)}} onPointerLeave={()=>setPointed('')}
         onFocus={()=>{setPointed('');setFocused(id)}} onBlur={()=>setFocused('')}
         onClick={()=>setChoice(id)}>
         <MeasuredGanttCode code={String(o.code)}/>
        </button>;
       })}
      </div>
     </div>
    </div>
    <div className="execution-chart-readout">
     {preview&&<>
      <div><strong><bdi>{String(preview.code)}</bdi></strong><span dir="auto">{name(preview)}</span></div>
      <div><span><bdi>{interval(preview)}</bdi></span><small>{t(executionStatus(preview))}</small></div>
     </>}
    </div>
   </div>
   <label className="execution-accessible-choice">{t('executionAccessibleSelection')}<select aria-label={t('executionAccessibleSelection')} value={chosen?choice:''} onChange={e=>setChoice(e.target.value)}><option value="" disabled>{t('select')}</option>{timeline.slots.map(({order:o}:{order:Row})=><option key={String(o.id)} value={String(o.id)}>{String(o.code)} · {name(o)} · {time(o.start_time)} · {barStatus(o)}</option>)}</select></label>
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
