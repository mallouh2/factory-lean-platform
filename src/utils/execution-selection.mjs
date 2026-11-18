export const executionScheduled=o=>Boolean(o.line_id&&o.start_time&&o.expected_finish&&Date.parse(o.expected_finish)>Date.parse(o.start_time));
export const executionLine=o=>o.actual_line_id||o.line_id;
export const executionStatus=o=>o.execution_interrupted_at?'f341Paused':o.status==='active'?'executionInProduction':String(o.status);
export const executionCandidate=o=>executionScheduled(o)&&['planned','active'].includes(o.status)&&!o.actual_finish&&typeof o.execution_remaining_quantity==='string'&&/^\d+(\.\d+)?$/.test(o.execution_remaining_quantity)&&/[1-9]/.test(o.execution_remaining_quantity);
export function selectedExecution(items,line,id){const rows=items.filter(o=>String(executionLine(o))===String(line)&&executionCandidate(o));return rows.find(o=>String(o.id)===String(id))||rows.find(o=>o.status==='active')||rows[0]||null;}
// Pack only true intervals. Details and accessible short-order targets live
// outside the time track, so annotation width cannot displace sequential work.
export function executionTimeline(items,pixelsPerHour=64,rowHeight=56){
 const rows=items.filter(executionCandidate).map((o,n)=>({order:o,index:n,start:Date.parse(o.start_time),finish:Date.parse(o.expected_finish)})).sort((a,b)=>a.start-b.start||a.index-b.index);
 if(!rows.length)return {from:0,until:0,width:720,height:0,slots:[],ticks:[]};
 const hour=3600000,from=Math.floor(Math.min(...rows.map(r=>r.start))/hour)*hour,until=Math.max(Math.ceil(Math.max(...rows.map(r=>r.finish))/hour)*hour+hour,from+Math.ceil(720/pixelsPerHour)*hour),width=(until-from)/hour*pixelsPerHour,ends=[];
 const slots=rows.map(r=>{const left=(r.start-from)/(until-from)*width,duration=(r.finish-r.start)/(until-from)*width;let row=ends.findIndex(end=>end<=r.start);if(row<0)row=ends.length;ends[row]=r.finish;return {...r,left,width:duration,row};});
 const step=pixelsPerHour<24?Math.ceil(180/(pixelsPerHour*24))*24:Math.max(1,Math.ceil(180/pixelsPerHour)),ticks=[];for(let t=from;t<until;t+=step*hour)ticks.push({at:t,left:(t-from)/(until-from)*width});
 return {from,until,width,height:68+ends.length*rowHeight,slots,ticks};
}
// A page is never a complete selector: bind all pages to one factory/revision,
// reject duplicates or changed lists, and enable commands only after completion.
export async function collectExecutionOrders(read,factory){const rows=[],ids=new Set();let cursor=null,revision=null,total=null;
 for(let page=0;page<500;page++){
  const data=await read(cursor);
  if(!data||data.factory!==factory||!Array.isArray(data.rows)||data.rows.length>100||!/^[a-f0-9]{64}$/.test(data.revision||'')||!Number.isSafeInteger(data.total)||data.total<0||data.total>50000
   ||revision!==null&&(data.revision!==revision||data.total!==total))throw Error('execution_orders_changed');
  revision=data.revision;total=data.total;
  for(const o of data.rows){if(o.factory_id!==factory||!o.id||ids.has(o.id)||!executionScheduled(o))throw Error('execution_orders_changed');ids.add(o.id);rows.push(o);}
  if(rows.length>total)throw Error('execution_orders_changed');
  if(data.complete===true){if(data.next_cursor!==null||rows.length!==total)throw Error('execution_orders_changed');return rows;}
  if(data.complete!==false||!data.next_cursor||data.rows.length!==100||data.next_cursor.revision!==revision||data.next_cursor.factory!==factory||data.next_cursor.after_id!==rows.at(-1).id)throw Error('execution_orders_changed');
  cursor=data.next_cursor;
 }
 throw Error('execution_orders_changed');
}
