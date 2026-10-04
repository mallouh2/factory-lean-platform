export const inventoryColumns = [
 ['name','name','text'],['code','code','text'],['item_type','inventoryType','set'],['supply_source','supplySource','set'],['unit','unit','set'],
 ['on_hand','stock_on_hand','number'],['semi_finished','inventorySemiFinished','number'],['in_production','inventoryInProduction','number'],['reserved','stock_reserved','number'],['available','stock_available','number'],['incoming','stock_incoming','number'],
 ['projected','stock_projected','number'],['minimum_stock','stockMin','number'],['maximum_stock','stockMax','number'],
 ['replenishment_status','status','set']
];
// Presentation only: the full column contract above still validates backend data.
const warehouseTitles={name:'item',item_type:'warehouseType',semi_finished:'warehouseSemi',minimum_stock:'warehouseMinimum',maximum_stock:'warehouseMaximum'};
export const warehouseVisibleColumns = inventoryColumns.filter(([key])=>!['supply_source','incoming','projected'].includes(key)).map(([key,title,type])=>[key,warehouseTitles[key]||title,type]);
export const inventoryChoices = {
 item_type:['FINISHED_GOOD','MANUFACTURED_INTERMEDIATE','RAW_MATERIAL','ACCESSORY','PACKAGING','SEMI_FINISHED'], supply_source:['MANUFACTURED','EXTERNAL','BOTH'],
 minimum_status:['AT_OR_BELOW_MIN','ABOVE_MIN','NOT_CONFIGURED'],
 replenishment_status:['AT_OR_BELOW_MIN','ABOVE_MIN','NOT_CONFIGURED','OK','PRODUCTION_REQUIRED','EXTERNAL_REQUIRED','SOURCING_REQUIRED','ALREADY_REQUESTED','PURCHASE_REQUESTED','INCOMING']
};
export function validInventoryFilters(filters) {
 if (!filters || typeof filters!=='object' || Array.isArray(filters) || JSON.stringify(filters).length>12000) return false;
 return Object.entries(filters).every(([key,v])=>{
 const col=inventoryColumns.find(c=>c[0]===key);if(!col)return false;
 if(col[2]==='text')return typeof v==='string'&&v.length<=200;
 if(col[2]==='set')return Array.isArray(v)&&v.length<=100&&v.every(x=>typeof x==='string'&&x.length<=100);
 if(!v||typeof v!=='object'||Array.isArray(v))return false;
 if(['configured','not_configured','positive'].includes(v.op))return true;
 return ['eq','gt','lt','range'].includes(v.op)&&Number.isFinite(v.value)&&(v.op!=='range'||(Number.isFinite(v.to)&&v.to>=v.value));
 });
}
