import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, verifyOrigin } from '@/services/authorization';
import { historyError, historyUuid } from '@/services/history-response';
import { operatingRuntime, runtimeByShift, comparableExposure, metricChange } from '@/utils/lean-analysis.mjs';
import { measuredHours, typedTotals } from '@/utils/lean-comparison.mjs';
import { annotateLeanAttention, leanDisplayStatus } from '@/utils/lean-presentation.mjs';
export async function GET(req:NextRequest) {
  try {
    const context=await authenticatedClient(),factory=historyUuid(req.nextUrl.searchParams.get('factory'));
    const status=req.nextUrl.searchParams.get('initiative_status');
    if(status&&!['OCCURRENCE','IN_PROGRESS','AWAITING_VERIFICATION','VERIFIED'].includes(status))throw {code:'22023'};
    const query=Object.fromEntries([...req.nextUrl.searchParams].filter(([k,v])=>!['factory','initiative_status'].includes(k)&&v!==''));
    await authorize(factory,['recording_review','recording_context'].includes(query.mode)?'orders':'lean','view',context);
    const read=async(q:Record<string,unknown>)=>{const {data,error}=await context.db.rpc('lean_read',{factory,query:q});if(error)throw error;return data;};
    const main=!query.mode||query.mode==='problems';
    const body=await read(main?{...query,mode:'problem_aggregates',page:1}:query);
    if(query.mode==='detail') {
      const collect=async(q:Record<string,unknown>)=>{const rows:any[]=[];for(let page=1;page<=100;page++){const data=await read({...q,page});if(data.source_revision!==body.source_revision)throw {code:'40001'};rows.push(...data.rows);if(rows.length>=data.total)return rows;}throw {code:'22023'};};
      const [events,entries]=await Promise.all([collect({...query,mode:'occurrences'}),collect({mode:'entries',from:query.from,to:query.to})]);
      const problem=body.problem,products=[...new Set(events.map(e=>e.product_id).filter(Boolean))];
      const output=entries.filter(e=>products.includes(e.product_id)&&(problem.machine_id?e.work_center_id===problem.machine_id||e.machine_ids?.includes(problem.machine_id):e.line_id===problem.line_id));
      const sum=(rows:any[],key:string)=>rows.every(x=>x[key]!=null)?rows.reduce((n,x)=>n+Number(x[key]),0):null;
      const scrap=sum(events,'scrap_kg'),weight=output.length?sum(output,'produced_weight_kg'):null;
      body.metrics={frequency:new Set(events.map(e=>e.event_id)).size,loss_minutes:sum(events,'loss_minutes'),scrap_kg:scrap,
        scrap_rate:weight&&scrap!=null?100*scrap/weight:null,lost_output_by_unit:typedTotals(events,'lost_output'),
        wip_by_unit:typedTotals(events,'wip_quantity'),shifts:[...new Set(events.map(e=>e.shift_id||null))]};
      body.shift_summary=[...new Set(events.map(e=>e.shift_id||null))].map(shift_id=>{
        const rows=events.filter(e=>(e.shift_id||null)===shift_id),produced=output.filter(e=>(e.shift_id||null)===shift_id);
        const scrap=sum(rows,'scrap_kg'),weight=produced.length?sum(produced,'produced_weight_kg'):null;
        const durations=rows.map(e=>Math.max(0,Date.parse(e.ended_at)-Date.parse(e.occurred_at))/60000).filter(Number.isFinite);
        return {shift_id,frequency:new Set(rows.map(e=>e.event_id)).size,loss_minutes:sum(rows,'loss_minutes'),scrap_kg:scrap,scrap_rate:weight&&scrap!=null?100*scrap/weight:null,lost_output:typedTotals(rows,'lost_output'),response_minutes:durations.length?durations.reduce((n,x)=>n+x,0)/durations.length:null};
      });
    }
    if (main && body.rows?.length) {
      const to=query.to || new Date().toISOString(),from=query.from || new Date(Date.now()-30*86400000).toISOString();
      const collect=async(q:Record<string,unknown>,limit=100)=>{const rows:any[]=[];for(let page=1;page<=limit;page++){const data=await read({...q,page});if(data.source_revision!==body.source_revision)throw {code:'40001'};rows.push(...data.rows);if(rows.length>=data.total)return rows;}throw {code:'22023'};};
      const [problems,rows,events,entries]=await Promise.all([collect({...query,mode:'problem_aggregates'}),collect({mode:'contexts',from:'1970-01-01T00:00:00Z',to}),collect({...Object.fromEntries(Object.entries(query).filter(([k])=>['line_id','machine_id','product_id','cause_id','shift_id'].includes(k))),mode:'analysis_occurrences',from:'1970-01-01T00:00:00Z',to}),collect({mode:'entries',from,to,...(query.product_id?{product_id:query.product_id}:{})})]);
      let complete=true;
      // A period predating capture has unknown exposure, even when a partial interval exists.
      complete=complete&&rows.length>0&&Date.parse(String(rows[0].captured_at))<=Date.parse(from);
      const intervals=runtimeByShift(operatingRuntime(rows as Parameters<typeof operatingRuntime>[0],to),rows).filter(x=>!query.shift_id||x.shift_id===query.shift_id);
      const hasLinkedScrap=problems.some((row:any)=>row.mechanism==='downtime'&&Number(row.scrap_kg)>0);
      const readTable=async(table:string,columns:string)=>{const rows:any[]=[];for(let page=0;page<100;page++){
        const {data,error}=await context.db.from(table).select(columns).eq('factory_id',factory).order('id').range(page*100,page*100+99);
        if(error)throw error;rows.push(...data);if(data.length<100)return rows;}throw {code:'22023'};};
      const [links,startups,assessmentEntries]=hasLinkedScrap?await Promise.all([
        readTable('lean_scrap_events','entry_id,downtime_id,approved_cause_id,occurred_at'),
        readTable('lean_startups','id,standard_kg'),collect({mode:'entries',from:'1970-01-01T00:00:00Z',to})
      ]):[[],[],[]];
      if(hasLinkedScrap&&(await read({mode:'entries',from:to,to})).source_revision!==body.source_revision)throw {code:'40001'};
      const enriched=problems.map((row:any)=>{
        const hours=complete?measuredHours(intervals,row.machine_id||row.line_id,row.products,from,to):null;
        const matching=events.filter(e=>e.mechanism===row.mechanism&&e.machine_id===row.machine_id&&e.cause_id===row.cause_id&&(row.mechanism==='downtime'||e.line_id===row.line_id&&e.product_id===row.product_id));
        const affected=[...new Set([...(row.products||[]),...matching.flatMap(e=>e.loss_details?.assumptions?.map((x:any)=>x.product_id)||[])])].filter(Boolean);
        const output=entries.filter(e=>(row.products||[]).includes(e.product_id)&&(!query.shift_id||e.shift_id===query.shift_id)&&(row.machine_id?e.work_center_id===row.machine_id||e.machine_ids?.includes(row.machine_id):e.line_id===row.line_id));
        const weight=output.length&&output.every(e=>e.produced_weight_kg!=null)?output.reduce((n,e)=>n+Number(e.produced_weight_kg),0):null;
        const trends=affected.map((product_id:string)=>{
          const exposure=complete?measuredHours(intervals,row.machine_id||row.line_id,[product_id],from,to):0;
          if(!exposure)return {product_id,complete:false};
          const before=comparableExposure(intervals,{subject_id:row.machine_id||row.line_id,product_id,cutoff:from,direction:'before',desired_hours:exposure});
          const start=before.intervals[0]?.started_at;
          const totals=(a:string,b:string)=>{const window=matching.filter(e=>Date.parse(e.occurred_at)>=Date.parse(a)&&Date.parse(e.occurred_at)<Date.parse(b)),group=window.filter(e=>e.product_id===product_id);if(window.some(e=>!e.product_id&&e.loss_details?.assumptions?.some((x:any)=>x.product_id===product_id)))return {frequency:null,loss_minutes:null,scrap_kg:null};return {frequency:new Set(group.map(e=>e.event_id)).size,loss_minutes:group.every(e=>e.loss_minutes!=null)?group.reduce((n,e)=>n+Number(e.loss_minutes),0):null,scrap_kg:group.every(e=>e.scrap_kg!=null)?group.reduce((n,e)=>n+Number(e.scrap_kg),0):null};};
          const prior=start?totals(start,from):null,current=totals(from,to);
          return {product_id,complete:before.complete,exposure_hours:exposure,frequency:metricChange(before.complete?prior?.frequency:null,current.frequency,row.threshold_percent),loss:metricChange(before.complete?prior?.loss_minutes:null,current.loss_minutes,row.threshold_percent),scrap:metricChange(before.complete?prior?.scrap_kg:null,current.scrap_kg,row.threshold_percent)};
        });
        return {...row,event_ids:matching.filter(e=>Date.parse(e.occurred_at)>=Date.parse(from)&&Date.parse(e.occurred_at)<Date.parse(to)).map(e=>e.event_id),products:affected,scrap_rate:weight>0&&row.missing_scrap===0?100*Number(row.scrap_kg)/weight:null,runtime_hours:hours,loss_rate:hours&&row.loss_minutes!=null&&row.missing_loss===0?Number(row.loss_minutes)/hours:null,frequency_rate:hours?Number(row.frequency)/hours:null,
          runtime_missing:!complete,trends};
      });
      const sort=['loss_minutes','scrap_kg','frequency','loss_rate'].includes(query.sort)?query.sort:'loss_minutes';
      enriched.sort((a:any,b:any)=>{if(a[sort]==null)return b[sort]==null?String(a.cause_id).localeCompare(String(b.cause_id)):1;if(b[sort]==null)return -1;return (Number(a[sort])-Number(b[sort]))*(query.direction==='asc'?1:-1)||String(a.cause_id).localeCompare(String(b.cause_id));});
      const eligible=status?enriched.filter(row=>leanDisplayStatus(row)===status):enriched;
      const presented=annotateLeanAttention(eligible,{entries:assessmentEntries,startups,links,from,to});
      const page=Number(query.page||1);if(!Number.isSafeInteger(page)||page<1)throw {code:'22023'};
      body.rows=presented.slice((page-1)*25,page*25);body.total=eligible.length;body.page=page;body.page_size=25;
      if(status)body.summary={...body.summary,loss_minutes:eligible.some(row=>row.loss_minutes!=null)?eligible.reduce((n,row)=>n+Number(row.loss_minutes||0),0):null,missing_loss:eligible.reduce((n,row)=>n+Number(row.missing_loss||0),0),recurring:eligible.filter(row=>Number(row.frequency)>=2).length};
    }
    return NextResponse.json(body,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return historyError(error);}
}
export async function POST(req:NextRequest) {
  try {
    verifyOrigin(req);const context=await authenticatedClient(),body=await req.json();
    historyUuid(body.factory);await authorize(body.factory,'lean','view',context);
    const {data:{session}}=await context.db.auth.getSession();
    if(!session)throw new Error('unauthorized');
    const response=await fetch(`${process.env.SUPABASE_URL}/functions/v1/lean-comparison`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${session.access_token}`,apikey:process.env.SUPABASE_PUBLISHABLE_KEY!},body:JSON.stringify(body)});
    const result=await response.json();return NextResponse.json(result,{status:response.status,headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return historyError(error);}
}
