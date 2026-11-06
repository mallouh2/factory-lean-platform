import {reconciliationMessage} from '@/utils/output-reconciliation.mjs';
export type FindingGroup={id:string;quantity:string;released?:string;missing_operations:string[];restriction?:string};
export type OutputAccountingState={pending:boolean;stage:string;applied?:{groups:FindingGroup[]};finding_id:string;remaining_handoff?:string;held_groups:string[];blockers:string[];affected_allocations?:{item_id:string;quantity:string}[]};
export default function OutputAccounting({accounting,finding,operations,unit,lang,details=false}:{accounting?:OutputAccountingState;finding?:{groups:FindingGroup[];reason?:string}|null;operations:Record<string,{name:string;name_ar?:string}>;unit:string;lang:string;details?:boolean}){
 if(!accounting)return null;
 const ar=lang==='ar',say=(en:string,arabic:string)=>ar?arabic:en;
 const groups=(items:FindingGroup[])=>items.map(g=><li key={g.id}><bdi>{g.quantity} {unit}</bdi> · {g.missing_operations.length?g.missing_operations.map(id=>ar?operations[id]?.name_ar||operations[id]?.name:operations[id]?.name).join(' + '):say('Finished','مكتمل')}</li>);
 return <div className="output-accounting" role="status">
  <strong>{accounting.pending?say('Reconciliation required','التسوية مطلوبة'):say('Applied','مطبق')}</strong>
  {accounting.pending&&<><p>{say('Quality’s finding is authoritative. Inventory actions are not yet complete.','قرار الجودة نافذ. لم تكتمل إجراءات المخزون بعد.')}</p>{accounting.blockers?.filter(code=>code!=='output_reconciliation_required').map(code=><p key={code}>{reconciliationMessage(code,lang)}</p>)}</>}
  {details&&<><h4>{say('Latest Quality finding','أحدث قرار للجودة')}</h4><ul>{groups(finding?.groups||[])}</ul>{finding?.reason&&<p dir="auto">{finding.reason}</p>}
   <h4>{say('Accounting classification applied','التصنيف المطبق محاسبياً')}</h4><ul>{groups(accounting.applied?.groups||[])}</ul><p>{say('These classifications are not proof of physical receipt. See received and outstanding quantities in Production Receipts.','هذه التصنيفات ليست إثبات استلام فعلي. راجع المستلم والمتبقي في استلام الإنتاج.')}</p></>}
 </div>;
}
