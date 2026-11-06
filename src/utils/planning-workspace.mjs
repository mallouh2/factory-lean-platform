// Presentation only. Eligibility and schedule writes remain in Planning V2/SQL.
export function planningWorkKind(order,request,work){
 if(work?.choice==='COMPLETE')return {type:'planningWorkCompletion',origin:'planningOriginCompletion'};
 if(work?.choice==='REPLACE'||order?.quality_origin_rejection_id||order?.replacement_original_item_id)return {type:'planningWorkReplacement',origin:'planningOriginQuality'};
 if(work?.choice==='STOCK')return {type:'planningWorkStockRecovery',origin:'planningOriginCompletion'};
 if(request?.request_type==='STOCK_REPLENISHMENT')return {type:'planningWorkStock',origin:'warehouse'};
 if(request?.request_type==='INTERNAL_PRODUCTION')return {type:'planningWorkStock',origin:'internalProduction'};
 return {type:'planningWorkNormal',origin:request?.request_type==='SALES_PRODUCTION'?'sales':null};
}
export function planningTiming(order, request, now = Date.now()) {
  if (['completed', 'cancelled'].includes(order.status)) return null;
  const finish = Date.parse(order.expected_finish || '');
  const required = Date.parse(request?.required_by || '');
  if (required < now) return 'planningDemandOverdue';
  if (finish < now) return 'planningFinishOverdue';
  if (order.status === 'planned' && Date.parse(order.start_time || '') < now)
    return 'planningStartOverdue';
  return null;
}

export function sortPlanningRows(items, requests, mode) {
  if (mode === 'priority') return items;
  const byId = new Map(requests.map(r => [String(r.id), r]));
  const date = value => Number.isFinite(Date.parse(value || '')) ? Date.parse(value) : Infinity;
  return [...items].sort((a, b) => {
    const difference = mode === 'required' ? date(byId.get(String(a.request_id))?.required_by) - date(byId.get(String(b.request_id))?.required_by)
      : mode === 'start' ? date(a.start_time) - date(b.start_time) : String(a.code || '').localeCompare(String(b.code || ''));
    return (Number.isNaN(difference) ? 0 : difference) || String(a.id).localeCompare(String(b.id));
  });
}
