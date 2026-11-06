import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
import {exactJsonNumbers} from './exact-json.mjs';
const uuid=value=>typeof value==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
export function completionQuery(query){
 if([...query.keys()].some(k=>!['factory','item'].includes(k)||query.getAll(k).length!==1)||!uuid(query.get('factory'))||!uuid(query.get('item')))throw{code:'22023'};
 return{factory:query.get('factory').toLowerCase(),item:query.get('item').toLowerCase()};
}
// Preserve numeric JSON tokens before postgrest-js parses this bounded row.
export function completionFetch(fetcher=globalThis.fetch){return async(input,init)=>{
 const response=await fetcher(input,init),url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
 if(!response.ok||!url.pathname.endsWith('/rest/v1/production_orders'))return response;
 const headers=new Headers(response.headers);headers.delete('content-length');headers.delete('content-encoding');
 return new Response(exactJsonNumbers(await response.text()),{status:response.status,statusText:response.statusText,headers});
};}
export function completionSummary(row,factory,item){
 if(!row||row.id!==item||row.factory_id!==factory)throw{code:'P0002'};
 const requested=decimalSubtract(row.target_quantity,'0'),recorded=decimalSubtract(row.good_quantity,'0');
 if(requested===null||recorded===null||decimalCompare(requested,'0')===-1||decimalCompare(recorded,'0')===-1||!['meter','piece','kg'].includes(row.unit))throw Error('recordingUnavailable');
 const produced=decimalSubtract(row.produced_good??recorded,'0'),remaining=decimalSubtract(row.ordinary_remaining??(decimalCompare(requested,recorded)===1?decimalSubtract(requested,recorded):'0'),'0');
 if(produced===null||remaining===null||decimalCompare(produced,'0')===-1||decimalCompare(remaining,'0')===-1)throw Error('recordingUnavailable');
 return{factory_id:factory,item_id:item,code:row.code,requested,recorded_good:recorded,produced_good:produced,makeup_committed:row.makeup_committed===true,
  remaining,unit:row.unit,status:row.status,
  actual_start:row.actual_start,actual_finish:row.actual_finish,request_id:row.request_id,
  replacement_original_item_id:row.replacement_original_item_id,quality_origin_rejection_id:row.quality_origin_rejection_id};
}
export function validCompletion(value,item){return !!value&&uuid(value.item)&&value.item===item&&typeof value.actual_start==='string'&&Number.isFinite(Date.parse(value.actual_start));}
export function sameExecutionStart(a,b){
 const part=x=>{if(typeof x!=='string'||!Number.isFinite(Date.parse(x)))return null;return Math.floor(Date.parse(x)/1000)+':'+((/\.(\d+)/.exec(x)?.[1]||'').padEnd(6,'0'));};
 return part(a)!==null&&part(a)===part(b);
}
