const uuid=value=>typeof value==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const object=value=>!!value&&typeof value==='object'&&!Array.isArray(value);
const fields={
 purchase_manual:['item_name','quantity','unit','details','notes','source_context'],
 purchase_stock:['item','quantity','unit','projected','notes'],
 purchase_inventory:['item','quantity','unit','details'],
 purchase_change:['id','revision','action','reason','supplier_id','supplier_text'],receive_purchase:['id','revision','reason'],
 supplier_save:['id','name','primary_contact','phone','email','notes','active','category','relationship','replace_primary'],
 material_request:['item','item_type','quantity','unit','note','production_item_id'],material_change:['id','revision','action','reason'],
 receive_wip:['lot','quantity'],acknowledge_good:['entry']
};
export function validSupplyFilters(value){
 return object(value)&&JSON.stringify(value).length<=12000&&Object.entries(value).every(([key,v])=>key==='status'
  ?Array.isArray(v)&&v.length<=8&&v.every(x=>['REQUESTED','UNDER_REVIEW','ORDERED','READY_FOR_RECEIPT','RECEIVED','NEEDS_CLARIFICATION','REJECTED','CANCELLED'].includes(x))
  :['search','code','item_name','requested_by_name','source_context'].includes(key)&&typeof v==='string'&&v.length<=200);
}
export function supplyCommandValid(command,args){
 if(!object(args)||!uuid(args.factory)||!uuid(args.request_id)||!object(args.payload)||JSON.stringify(args).length>50000)return false;
 if(command==='define_manufactured_product')return Object.keys(args).every(k=>['factory','product','payload','components','request_id'].includes(k))
  &&(args.product===null||uuid(args.product))&&Object.keys(args.payload).every(k=>['name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate','stage','product_kind','stock_unit','formula_product_id','unit_weight_kg'].includes(k))
  &&(args.components===null||(Array.isArray(args.components)&&args.components.length>0&&args.components.length<=100&&args.components.every(c=>object(c)&&Object.keys(c).every(k=>['material_id','quantity','unit'].includes(k))&&uuid(c.material_id)&&Number.isFinite(c.quantity)&&c.quantity>0&&c.unit==='kg')));
 return command==='supply_command'&&Object.keys(args).every(k=>['factory','action','payload','request_id'].includes(k))&&Object.hasOwn(fields,args.action)
  &&Object.keys(args.payload).every(k=>fields[args.action].includes(k));
}
