import {maintenanceVisualWindow} from './maintenance-planning-view.mjs';
// Presentation only. Label tracks never alter saved times or capacity protection.
export function ganttLayout(schedule,from,until,pixels=1000,maintenance=[]){
 const span=until-from,tracks=[],entries=[],unknown=[];
 if(!(span>0)||!(pixels>0))return {jobs:[],reservations:[],unknown,tracks:0};
 function add(entry,start,finish){
  if(start>=until||(finish!==null&&finish<=from))return;
  const left=(Math.max(from,start)-from)/span*100,width=finish===null?0:(Math.min(until,finish)-Math.max(from,start))/span*100;
  const markerStart=left/100*pixels,markerEnd=(left+width)/100*pixels;
  const captionWidth=entry.reservation?148:168,captionGap=entry.reservation?0:12;
  const compact=width/100*pixels<captionWidth,captionEnd=compact&&markerEnd+captionGap+captionWidth>pixels;
  const captionStart=entry.reservation?(captionEnd?markerEnd-captionWidth:markerStart):(captionEnd?markerStart-captionGap-captionWidth:markerEnd+captionGap);
  // Pack the union of exact time geometry, connector and annotation, not just
  // the caption. Stable ordering keeps adjacent short jobs apart on refresh.
  const a=compact?Math.min(markerStart,captionStart):markerStart;
  const b=compact?Math.max(markerEnd,captionStart+captionWidth):markerEnd;
  entries.push({...entry,start,finish,left,width,compact,captionEnd,a,b});
 }
 for(const slot of schedule){
  const start=Date.parse(slot.order.start_time||''),savedFinish=Date.parse(slot.order.expected_finish||'');
  if(!Number.isFinite(start)){unknown.push(slot.order);continue;}
  add(slot,start,Number.isFinite(savedFinish)&&savedFinish>start?savedFinish:null);
 }
 for(const reservation of maintenance){const window=maintenanceVisualWindow(reservation);if(reservation.occupancy?.continues)window.finish=Math.max(window.finish,until);
  if(Number.isFinite(window.start)&&Number.isFinite(window.finish))add({reservation},window.start,window.finish);
 }
 entries.sort((a,b)=>a.a-b.a||a.start-b.start||String(a.order?.id||a.reservation.id).localeCompare(String(b.order?.id||b.reservation.id)));
 for(const entry of entries){let track=tracks.findIndex(end=>end+8<=entry.a);if(track<0)track=tracks.length;tracks[track]=entry.b;entry.track=track;}
 return {jobs:entries.filter(x=>x.order),reservations:entries.filter(x=>x.reservation),unknown,tracks:tracks.length};
}
export function ganttFocusStart(orders,now,span){
 const starts=orders.map(o=>Date.parse(o.start_time||'')).filter(Number.isFinite).sort((a,b)=>a-b);
 const target=starts.find(start=>start>=now)??starts.at(-1);
 return target===undefined?null:target-span*.05;
}
