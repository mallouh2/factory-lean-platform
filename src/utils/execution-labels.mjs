// Annotation lanes are independent of production lanes and true bar geometry.
// A readable label never moves sequential work onto another execution track.
export function executionLabels(timeline,measured={},labelWidth=200){
 const ends=[],slots=timeline.slots.map(slot=>{
  const fits=Number.isFinite(measured[slot.order.id])&&slot.width>=measured[slot.order.id]+12;
  if(fits)return {...slot,fits,labelLane:0,labelLeft:slot.left};
  const labelLeft=Math.max(0,Math.min(slot.left,timeline.width-labelWidth));
  const lanes=ends[slot.row]||[];let lane=lanes.findIndex(end=>end+12<=labelLeft);if(lane<0)lane=lanes.length;
  lanes[lane]=labelLeft+labelWidth;ends[slot.row]=lanes;
  return {...slot,fits,labelLane:lane,labelLeft};
 });
 const rowHeight=Math.max(56,52+Math.max(0,...ends.map(r=>r.length))*48);
 return{slots:slots.map(s=>({...s,barTop:52+s.row*rowHeight,labelTop:98+s.row*rowHeight+s.labelLane*48})),height:Math.max(timeline.height,68+(Math.max(0,...slots.map(s=>s.row))+1)*rowHeight)};
}
