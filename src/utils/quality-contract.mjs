const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const object=value=>value!==null&&typeof value==='object'&&!Array.isArray(value);
export const qualityOperations={reject:['source','quantity','reason','disposition','actual_scrap_kg','description','approve_reason','note','physically_identified'],
 reverse:['rejection','physically_present','reason'],reason:['id','name','name_ar','active'],acknowledge:['rejection'],resolve:['rejection'],
 request_rework:['rejection','lot','quantity'],replacement:['rejection','quantity']};
export function qualityRequiredPermissions(operation){
 if(operation==='reject')return [['quality','view'],['quality','create']];
 if(operation==='reverse')return [['quality','view'],['quality','edit']];
 if(operation==='reason')return [['quality','view'],['quality_reasons','edit']];
 return [['orders','view'],['orders',operation==='replacement'?'create':'edit']];
}
export function sourceRequiredPermissions(operation){return operation==='correct'?[['orders','view'],['orders','edit']]:
 [['warehouse',['identify','mix','adjust'].includes(operation)?'edit':'issue']];}
export function qualityCommandValid(args) {
 return object(args)&&Object.keys(args).every(k=>['factory','operation','payload','request_id'].includes(k))&&uuid(args.factory)&&uuid(args.request_id)&&
  object(args.payload)&&Object.hasOwn(qualityOperations,args.operation)&&Object.keys(args.payload).every(k=>qualityOperations[args.operation].includes(k))&&
  ['source','rejection','lot','id'].every(k=>args.payload[k]===undefined||args.payload[k]===null||uuid(args.payload[k]));
}
export function sourceCommandValid(args) {
 const fields={identify:['source','quantity','label','physically_identified','note'],mix:['source','quantity','physically_identified','note'],
  reserve:['sales_line_id'],dispatch:['sales_order','line'],adjust:['product','unit','quantity','reason'],issue:['id','revision','reason'],
  correct:['entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work']};
 return object(args)&&Object.keys(args).every(k=>['factory','operation','payload','allocations','request_id'].includes(k))&&uuid(args.factory)&&uuid(args.request_id)&&
  object(args.payload)&&Object.hasOwn(fields,args.operation)&&Object.keys(args.payload).every(k=>fields[args.operation].includes(k))&&
  ['source','sales_line_id','sales_order','line','product','id','entry','shift'].every(k=>args.payload[k]===undefined||args.payload[k]===null||uuid(args.payload[k]))&&Array.isArray(args.allocations)&&args.allocations.length<=100&&
  args.allocations.every(pick=>object(pick)&&Object.keys(pick).every(k=>['source_id','quantity','sales_line_id'].includes(k))&&
   (pick.source_id===null||uuid(pick.source_id))&&(pick.sales_line_id===undefined||uuid(pick.sales_line_id))&&typeof pick.quantity==='string'&&pick.quantity.length<=2048);
}
