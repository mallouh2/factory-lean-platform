import {maintenanceVisualWindow} from './maintenance-planning-view.mjs';
// Presentation only. Saved intervals own stable tracks; hidden compact caption
// metadata must not move actual time bars or change lanes during zoom/pan.
export function ganttLayout(schedule,from,until,pixels=1000,maintenance=[]){
 const span=until-from,tracks=[],entries=[],unknown=[];
 if(!(span>0)||!(pixels>0))return {jobs:[],reservations:[],unknown,tracks:0};
 function add(entry,start,finish){
  entries.push({...entry,start,finish});
 }
 for(const slot of schedule){
  const start=Date.parse(slot.order.start_time||''),savedFinish=Date.parse(slot.order.expected_finish||'');
  if(!Number.isFinite(start)){unknown.push(slot.order);continue;}
  add(slot,start,Number.isFinite(savedFinish)&&savedFinish>start?savedFinish:null);
 }
 for(const reservation of maintenance){const window=maintenanceVisualWindow(reservation);
  if(Number.isFinite(window.start)&&Number.isFinite(window.finish))add({reservation,continues:reservation.occupancy?.continues},window.start,window.finish);
 }
 entries.sort((a,b)=>a.start-b.start||String(a.order?.id||a.reservation.id).localeCompare(String(b.order?.id||b.reservation.id)));
 // Pack the full saved schedule before viewport clipping. Zoom, pan, label
 // width and backend row order cannot change an item's track identity.
 const intervals=[];
 for(const entry of entries.filter(e=>e.order)){let track=tracks.findIndex(end=>end<=entry.start);if(track<0){track=tracks.length;intervals.push([]);}const end=entry.finish??entry.start;tracks[track]=end;intervals[track].push([entry.start,end]);entry.track=track;}
 // Range-scoped maintenance annotations may arrive after a pan. They can use
 // gaps or additional tracks, but must never displace the production lane.
 for(const entry of entries.filter(e=>e.reservation)){const end=entry.continues?Infinity:entry.finish;let track=intervals.findIndex(segments=>segments.every(([a,b])=>b<=entry.start||end<=a));if(track<0){track=intervals.length;intervals.push([]);}intervals[track].push([entry.start,end]);entry.track=track;}
 const visible=entries.filter(e=>e.start<until&&(e.finish===null||e.continues||e.finish>from));
 for(const entry of visible){
  const start=entry.start,finish=entry.continues?Math.max(entry.finish,until):entry.finish;entry.finish=finish;
  const left=(Math.max(from,start)-from)/span*100,width=finish===null?0:(Math.min(until,finish)-Math.max(from,start))/span*100;
  const markerStart=left/100*pixels,markerEnd=(left+width)/100*pixels;
  const captionWidth=entry.reservation?148:168,captionGap=entry.reservation?0:12;
  const compact=width/100*pixels<captionWidth,captionEnd=compact&&markerEnd+captionGap+captionWidth>pixels;
  const captionStart=entry.reservation?(captionEnd?markerEnd-captionWidth:markerStart):(captionEnd?markerStart-captionGap-captionWidth:markerEnd+captionGap);
  const a=compact?Math.min(markerStart,captionStart):markerStart;
  const b=compact?Math.max(markerEnd,captionStart+captionWidth):markerEnd;
  Object.assign(entry,{left,width,compact,captionEnd,a,b});
 }
 const count=visible.length?Math.max(...visible.map(e=>e.track))+1:0;
 return {jobs:visible.filter(x=>x.order),reservations:visible.filter(x=>x.reservation),unknown,tracks:count};
}
export function ganttFocusStart(orders,now,span){
 const starts=orders.map(o=>Date.parse(o.start_time||'')).filter(Number.isFinite).sort((a,b)=>a-b);
 const target=starts.find(start=>start>=now)??starts.at(-1);
 return target===undefined?null:target-span*.05;
}
