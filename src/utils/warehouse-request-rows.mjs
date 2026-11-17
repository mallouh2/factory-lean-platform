// Shared display projection for the queue and its protected export. No writes.
import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
/** @param {{materials?:any[],receipts?:any[],legacy?:any[],orders?:any[],dispatchable?:Record<string,string>,lang?:string,statusScope?:string,t:(key:string)=>string}} input */
export function warehouseRequestRows({materials=[],receipts=[],legacy=[],orders=[],dispatchable={},lang='en',t,statusScope='active'}){
 const say=(en,ar)=>lang==='ar'?ar:en;
 return [
  ...materials.map(r=>({id:String(r.id),reference:String(r.code||String(r.id).slice(0,8)),kind:r.item_type==='lot'?'unfinished':'issue',department:t('production'),name:String(r.item_name||r.name||''),quantity:String(r.quantity),unit:String(r.unit),available:r.available_quantity==null?'—':String(r.available_quantity),status:t('materialState_'+String(['CANCELLED','REJECTED'].includes(r.status)?r.status:r.preparation?.status||r.status)),completed:warehouseIssueCompleted(r),material:r})),
  ...receipts.filter(r=>r.groups?.some(g=>Number(g.remaining)>0)||r.accounting?.pending).map(r=>({id:r.id,reference:r.order,kind:'receipt',department:t('production'),name:lang==='ar'?r.product_name_ar||r.product_name:r.product_name,quantity:r.groups.filter(g=>Number(g.remaining)>0).map(g=>(g.missing_operations?.length?say('Unfinished: ','غير مكتمل: '):say('Finished: ','مكتمل: '))+g.remaining).join(' · ')||'—',unit:r.unit,available:r.reconciliation_action?.blocker||r.accounting?.stage==='PENDING'?'0':say('Quality released','مصرح من الجودة'),status:r.reconciliation_action?.blocker||r.accounting?.stage==='PENDING'?say('Held — review required','موقوف — يتطلب مراجعة'):say('Awaiting receipt','بانتظار الاستلام'),receipt:r.id})),
  ...legacy.filter(r=>r.manufactured===false).map(r=>({id:String(r.id),reference:String(r.code),kind:'acknowledge',department:t('production'),name:String(lang==='ar'?r.name_ar||r.name:r.name),quantity:String(r.effective_good),unit:String(r.unit),available:say('Already credited','مضاف سابقاً للمخزون'),status:r.acknowledged?t('completed'):say('Physical acknowledgement pending','بانتظار تأكيد الاستلام الفعلي'),completed:Boolean(r.acknowledged),legacy:r})),
  ...orders.flatMap(order=>order.lines.filter(line=>decimalCompare(line.dispatched_quantity,line.quantity)===-1).map(line=>({id:line.id,reference:order.code,kind:'dispatch',department:t('navSales'),name:lang==='ar'?line.product_name_ar||line.product_name:line.product_name,quantity:decimalSubtract(line.quantity,line.dispatched_quantity),unit:line.unit,available:dispatchable[line.id]??'—',status:say('Outstanding','متبقٍ'),order,line})))
 ].map(r=>({...r,completed:r.completed??false,row_key:r.kind+':'+r.id})).filter(r=>statusScope==='all'||(statusScope==='completed'?r.completed:!r.completed));
}
export function warehouseIssueCompleted(r){const issued=r.preparation?.issued,comparison=issued==null?null:decimalCompare(String(issued),String(r.quantity));if(['CANCELLED','REJECTED'].includes(r.status)||r.preparation?.status==='CLOSED')return true;if(comparison!==null)return comparison===0||comparison===1;return ['ISSUED','RECEIVED'].includes(r.status)||r.preparation?.status==='ISSUED';}
export const warehouseReturnCompleted=r=>['RECEIVED','CANCELLED','REJECTED'].includes(r.status);
export const warehouseDeliveryCompleted=r=>Array.isArray(r.rows)&&r.rows.length>0&&r.rows.every(m=>{const c=decimalCompare(String(m.delivered),String(m.quantity));return c===0||c===1;});
export function warehouseRequestLabels(lang){
 const say=(en,ar)=>lang==='ar'?ar:en;
 return{'production-stock':say('Production material delivery','تسليم مواد للإنتاج'),'raw-return':say('Raw material return','إعادة مواد خام'),issue:say('Issue to Production','صرف للإنتاج'),unfinished:say('Issue unfinished material','صرف إنتاج غير مكتمل'),receipt:say('Receive inspected production','استلام إنتاج مفحوص'),acknowledge:say('Acknowledge production receipt','تأكيد استلام الإنتاج'),dispatch:say('Customer dispatch','إرسال للعميل')};
}
// Request identity is independent of its operational status.
export function warehouseRequestTone(kind){
 return ({'production-stock':'info','raw-return':'success',issue:'info',unfinished:'unfinished',receipt:'success',acknowledge:'warning',dispatch:'dispatch'})[kind]||'neutral';
}
