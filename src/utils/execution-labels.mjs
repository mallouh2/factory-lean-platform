// Pack annotations horizontally on ONE baseline, independently of real time.
// Extend the scroll surface rather than shifting bars or stacking labels.
export function executionLabels(timeline,measured={},labelWidth=200,labelHeight=48){
 let end=-12;
 const labelTop=98+Math.max(0,...timeline.slots.map(s=>s.row))*56;
 const slots=timeline.slots.map(slot=>{
  const fits=Number.isFinite(measured[slot.order.id])&&slot.width>=measured[slot.order.id]+12;
  const labelLeft=Math.max(slot.left,end+12);end=labelLeft+labelWidth;
  return {...slot,fits,labelLeft,labelTop,barTop:52+slot.row*56};
 });
 const width=Math.max(timeline.width,end),ticks=[...(timeline.ticks||[])];
 if(ticks.length>1){const step=ticks[1].left-ticks[0].left,period=ticks[1].at-ticks[0].at;while(ticks.at(-1).left+step<width){const last=ticks.at(-1);ticks.push({left:last.left+step,at:last.at+period});}}
 return{slots,width,ticks,height:Math.max(timeline.height,labelTop+Math.max(48,labelHeight)+16)};
}
