// Shared display projection for the queue and its protected export. No writes.
import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
/** @param {{materials?:any[],receipts?:any[],legacy?:any[],orders?:any[],dispatchable?:Record<string,string>,lang?:string,t:(key:string)=>string}} input */
export function warehouseRequestRows({materials=[],receipts=[],legacy=[],orders=[],dispatchable={},lang='en',t}){
 const say=(en,ar)=>lang==='ar'?ar:en;
 return [
  ...materials.filter(r=>r.status==='REQUESTED'||r.preparation&&r.preparation.status!=='CLOSED').map(r=>({id:String(r.id),reference:String(r.code||String(r.id).slice(0,8)),kind:r.item_type==='lot'?'unfinished':'issue',department:t('production'),name:String(r.item_name||r.name||''),quantity:String(r.quantity),unit:String(r.unit),available:r.available_quantity==null?'—':String(r.available_quantity),status:t('materialState_'+String(r.preparation?.status||r.status)),material:r})),
  ...receipts.filter(r=>r.groups?.some(g=>Number(g.remaining)>0)||r.accounting?.pending).map(r=>({id:r.id,reference:r.order,kind:'receipt',department:t('production'),name:lang==='ar'?r.product_name_ar||r.product_name:r.product_name,quantity:r.groups.filter(g=>Number(g.remaining)>0).map(g=>(g.missing_operations?.length?say('Unfinished: ','غير مكتمل: '):say('Finished: ','مكتمل: '))+g.remaining).join(' · ')||'—',unit:r.unit,available:r.reconciliation_action?.blocker||r.accounting?.stage==='PENDING'?'0':say('Quality released','مصرح من الجودة'),status:r.reconciliation_action?.blocker||r.accounting?.stage==='PENDING'?say('Held — review required','موقوف — يتطلب مراجعة'):say('Awaiting receipt','بانتظار الاستلام'),receipt:r.id})),
  ...legacy.filter(r=>r.manufactured===false).map(r=>({id:String(r.id),reference:String(r.code),kind:'acknowledge',department:t('production'),name:String(lang==='ar'?r.name_ar||r.name:r.name),quantity:String(r.effective_good),unit:String(r.unit),available:say('Already credited','مضاف سابقاً للمخزون'),status:say('Physical acknowledgement pending','بانتظار تأكيد الاستلام الفعلي'),legacy:r})),
  ...orders.flatMap(order=>order.lines.filter(line=>decimalCompare(line.dispatched_quantity,line.quantity)===-1).map(line=>({id:line.id,reference:order.code,kind:'dispatch',department:t('navSales'),name:lang==='ar'?line.product_name_ar||line.product_name:line.product_name,quantity:decimalSubtract(line.quantity,line.dispatched_quantity),unit:line.unit,available:dispatchable[line.id]??'—',status:say('Outstanding','متبقٍ'),order,line})))
 ].map(r=>({...r,row_key:r.kind+':'+r.id}));
}
export function warehouseRequestLabels(lang){
 const say=(en,ar)=>lang==='ar'?ar:en;
 return{issue:say('Issue to Production','صرف للإنتاج'),unfinished:say('Issue unfinished material','صرف إنتاج غير مكتمل'),receipt:say('Receive inspected production','استلام إنتاج مفحوص'),acknowledge:say('Acknowledge production receipt','تأكيد استلام الإنتاج'),dispatch:say('Customer dispatch','إرسال للعميل')};
}
// Request identity is independent of its operational status.
export function warehouseRequestTone(kind){
 return ({issue:'info',unfinished:'unfinished',receipt:'success',acknowledge:'warning',dispatch:'dispatch'})[kind]||'neutral';
}
