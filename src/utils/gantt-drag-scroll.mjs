// Timeline coordinates remain physical LTR even when the surrounding UI is RTL.
export function edgeSpeed(point,start,end,band=56){
 if(point<start||point>end||end<=start)return 0;
 const reach=Math.min(band,(end-start)/3);
 if(point<start+reach)return -720*(1-(point-start)/reach);
 if(point>end-reach)return 720*(1-(end-point)/reach);
 return 0;
}
export function startGanttDragScroll(event,chart){
 const doc=chart?.ownerDocument||document,win=doc.defaultView;
 let x=event.clientX,y=event.clientY,frame=0,last=0,stopped=false;
 const transfer=event.dataTransfer;
 function move(e){x=e.clientX;y=e.clientY;e.preventDefault();}
 function stop(){if(stopped)return;stopped=true;win.cancelAnimationFrame(frame);doc.removeEventListener('dragover',move,true);doc.removeEventListener('dragenter',move,true);doc.removeEventListener('drop',stop,true);doc.removeEventListener('dragend',stop,true);doc.removeEventListener('keydown',escape,true);}
 function escape(e){if(e.key==='Escape'){
 const page=doc.scrollingElement,positions=[page,chart].filter(Boolean).map(el=>({el,top:el.scrollTop,left:el.scrollLeft}));stop();
 // Native drag cancellation may reveal the original focused source. Retain the
 // viewport reached by the user, once, after that default focus operation.
 win.requestAnimationFrame(()=>positions.forEach(({el,top,left})=>el.scrollTo({top,left,behavior:'instant'})));
 }}
 function tick(now){if(stopped)return;const dt=Math.min((now-(last||now))/1000,.04);last=now;
  const hit=doc.elementFromPoint(x,y),ancestors=[];for(let el=hit;el;el=el.parentElement)ancestors.push(el);
  const page=doc.scrollingElement;let moved=false;
  function scrollAxis(axis){
   for(const el of [...ancestors.filter(el=>el!==page),page]){if(!el)continue;
    const vertical=axis==='y',style=win.getComputedStyle(el),overflow=vertical?style.overflowY:style.overflowX;
    if(el!==page&&!/auto|scroll/.test(overflow))continue;
    const max=vertical?el.scrollHeight-el.clientHeight:el.scrollWidth-el.clientWidth;if(max<=1)continue;
    // Do not scroll the document horizontally; the timeline owns horizontal movement.
    if(!vertical&&(!chart||!chart.contains(el)&&el!==chart))continue;
    const r=el===page?{left:0,top:0,right:win.innerWidth,bottom:win.innerHeight}:el.getBoundingClientRect();
    const start=Math.max(0,vertical?r.top:r.left),end=Math.min(vertical?win.innerHeight:win.innerWidth,vertical?r.bottom:r.right);
    const speed=edgeSpeed(vertical?y:x,start,end);if(!speed)continue;
    const before=vertical?el.scrollTop:el.scrollLeft;
    el.scrollBy({top:vertical?speed*dt:0,left:vertical?0:speed*dt,behavior:'instant'});
    const after=vertical?el.scrollTop:el.scrollLeft;if(after!==before){moved=true;break;}
   }
  }
  scrollAxis('y');scrollAxis('x');
  if(moved){const target=doc.elementFromPoint(x,y);target?.dispatchEvent(new win.DragEvent('dragover',{bubbles:true,cancelable:true,clientX:x,clientY:y,dataTransfer:transfer}));}
  frame=win.requestAnimationFrame(tick);
 }
 doc.addEventListener('dragover',move,true);doc.addEventListener('dragenter',move,true);doc.addEventListener('drop',stop,true);doc.addEventListener('dragend',stop,true);doc.addEventListener('keydown',escape,true);frame=win.requestAnimationFrame(tick);return stop;
}
