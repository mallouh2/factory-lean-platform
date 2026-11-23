import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, verifyOrigin } from '@/services/authorization';
import { historyError, historyUuid } from '@/services/history-response';
import { operatingRuntime, runtimeByShift, comparableExposure, metricChange } from '@/utils/lean-analysis.mjs';
import { measuredHours, windowMetrics } from '@/utils/lean-comparison.mjs';
import {productionScope} from '@/utils/production-periods.mjs';
import {consumerFetch} from '@/utils/production-consumer-transport.mjs';
import { annotateLeanAttention, leanDisplayStatus, leanLossRanking } from '@/utils/lean-presentation.mjs';
export async function GET(req:NextRequest) {
  try {
    const context=await authenticatedClient(consumerFetch()),factory=historyUuid(req.nextUrl.searchParams.get('factory'));
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
      const metrics=windowMetrics(events,entries,query.from||new Date(Date.now()-30*86400000).toISOString(),query.to||new Date().toISOString(),null,
        {product_id:problem.product_id||products[0],...(problem.mechanism==='downtime'?{product_ids:products}:{}),subject_id:problem.machine_id||problem.line_id,mechanism:problem.mechanism,evidence_version:body.evidence_version});
      body.metrics={...metrics,lost_output_by_unit:metrics.lost_output,wip_by_unit:metrics.wip,shifts:metrics.shifts.map(x=>x.shift_id)};
      body.shift_summary=metrics.shifts.map(x=>{const durations=x.response_minutes.map((r:{minutes:number|null})=>r.minutes).filter((v:number|null):v is number=>v!==null&&Number.isFinite(v));
        return {...x,lost_output:x.lost_output,response_minutes:durations.length?durations.reduce((a:number,b:number)=>a+b,0)/durations.length:null};});
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
        const output=entries.filter(e=>!query.shift_id||e.shift_id===query.shift_id);
        const currentMetrics=windowMetrics(matching,output,from,to,hours,{product_id:row.product_id||affected[0],...(row.mechanism==='downtime'?{product_ids:affected}:{}),subject_id:row.machine_id||row.line_id,mechanism:row.mechanism,evidence_version:body.evidence_version});
        const trends=affected.map((product_id:string)=>{
          const exposure=complete?measuredHours(intervals,row.machine_id||row.line_id,[product_id],from,to):0;
          if(!exposure)return {product_id,complete:false};
          const before=comparableExposure(intervals,{subject_id:row.machine_id||row.line_id,product_id,cutoff:from,direction:'before',desired_hours:exposure});
          const start=before.intervals[0]?.started_at;
          const totals=(a:string,b:string)=>windowMetrics(matching,output,a,b,null,{product_id,subject_id:row.machine_id||row.line_id,mechanism:row.mechanism,evidence_version:body.evidence_version});
          const prior=start?totals(start,from):null,current=totals(from,to);
          return {product_id,complete:before.complete,exposure_hours:exposure,frequency:metricChange(before.complete?prior?.frequency:null,current.frequency,row.threshold_percent),loss:metricChange(before.complete?prior?.loss_minutes:null,current.loss_minutes,row.threshold_percent),scrap:metricChange(before.complete?prior?.scrap_kg:null,current.scrap_kg,row.threshold_percent)};
        });
        const visibleEvents=matching.filter(e=>productionScope(e,from,to)!=='OUTSIDE');
        const quantified=visibleEvents.filter(e=>e.lost_output!=null&&e.output_unit);
        // The reader coalesces actual output over the estimate. Equal quantities
        // cannot prove which source was used, even if effective minutes are actual.
        const outputMeasured=row.mechanism==='downtime'&&quantified.length>0&&quantified.every(e=>
          e.loss_details?.estimated_lost_output_quantity==null||
          Number(e.loss_details.estimated_lost_output_quantity)!==Number(e.lost_output)||
          e.loss_details.unit!==e.output_unit);
        return {...row,event_ids:visibleEvents.map(e=>e.event_id),products:affected,output_measured:outputMeasured,
          ...(row.mechanism==='scrap'?{scrap_kg:currentMetrics.scrap_kg,frequency:currentMetrics.frequency}:{}),
          evidence_status:complete?currentMetrics.status:'INCOMPLETE',quantity_evidence_status:currentMetrics.status,scrap_rate:currentMetrics.scrap_rate,runtime_hours:hours,loss_rate:hours&&row.loss_minutes!=null&&row.missing_loss===0?Number(row.loss_minutes)/hours:null,frequency_rate:hours&&currentMetrics.frequency!==null?Number(currentMetrics.frequency)/hours:null,
          runtime_missing:!complete,trends};
      });
      const sort=['loss_minutes','scrap_kg','frequency','loss_rate'].includes(query.sort)?query.sort:'loss_minutes';
      enriched.sort((a:any,b:any)=>{if(a[sort]==null)return b[sort]==null?String(a.cause_id).localeCompare(String(b.cause_id)):1;if(b[sort]==null)return -1;return (Number(a[sort])-Number(b[sort]))*(query.direction==='asc'?1:-1)||String(a.cause_id).localeCompare(String(b.cause_id));});
      const eligible=status?enriched.filter(row=>leanDisplayStatus(row)===status):enriched;
      body.loss_ranking=leanLossRanking(eligible);
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
