import {sameExecutionStart} from '@/utils/production-completion.mjs';
import type {CompletionTarget} from './production-recording-client';
export type CompletionSummary={factory_id:string;item_id:string;code:string;requested:string;recorded_good:string;produced_good?:string;makeup_committed?:boolean;remaining:string;remaining_demand?:string|null;unit:string;status:string;actual_start:string|null;actual_finish:string|null;request_id:string;request_type?:string|null;replacement_original_item_id:string|null;quality_origin_rejection_id:string|null};
export async function readCompletion(factory:string,item:string,fetcher:typeof fetch=fetch):Promise<CompletionSummary>{
 const r=await fetcher('/api/production-completion?'+new URLSearchParams({factory,item}),{credentials:'same-origin',cache:'no-store',signal:AbortSignal.timeout(20000)}),body=await r.json();
 if(!r.ok||body.factory_id!==factory||body.item_id!==item||!['requested','recorded_good','remaining'].every(k=>typeof body[k]==='string'))throw Error(r.status===403||r.status===401?'permissionError':'prv3SummaryUnavailable');
 return body;
}
// Never resends recording. Reconcile a lost finish response by reading the
// same execution, rather than treating every network failure as a failed write.
export async function finishRecordedExecution(factory:string,target:CompletionTarget,command:(name:string,args:Record<string,unknown>)=>Promise<unknown>,fetcher:typeof fetch=fetch):Promise<CompletionSummary>{
 const check=(value:CompletionSummary)=>{if(!sameExecutionStart(value.actual_start,target.actual_start))throw Error('recordingContextChanged');return value;};
 const before=check(await readCompletion(factory,target.item,fetcher));
 if(before.status==='completed'&&before.actual_finish)return before;
 if(before.status!=='active'||before.actual_finish)throw Error('recordingContextChanged');
 let failure:unknown;
 try{await command('finish_product_item',{factory,item:target.item,expected_actual_start:target.actual_start});}catch(error){failure=error;}
 const after=check(await readCompletion(factory,target.item,fetcher));
 if(after.status==='completed'&&after.actual_finish)return after;
 throw failure instanceof Error?failure:Error('prv3FinishPending');
}
