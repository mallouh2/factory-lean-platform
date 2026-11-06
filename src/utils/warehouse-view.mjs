import {inventoryColumns} from './warehouse-inventory.mjs';
export const defaultWarehouseColumns=['name','item_type','on_hand','reserved','available','projected','replenishment_status'];
export const warehouseColumnChoices=[...defaultWarehouseColumns,'incoming','minimum_stock','maximum_stock','in_production','semi_finished','supply_source'];
export function visibleWarehouseColumns(value){
 const selected=Array.isArray(value)?warehouseColumnChoices.filter(key=>value.includes(key)):[];
 return selected.length?selected:defaultWarehouseColumns;
}
export const warehousePreferenceKey=(actor,factory)=>actor&&factory?`factorylean:table:v2:warehouse:${encodeURIComponent(actor)}:${encodeURIComponent(factory)}`:null;
export const warehouseColumnTitle=key=>({on_hand:'whPhysicalOnHand',reserved:'whReservedOrders',available:'whAvailable',projected:'whProjected',name:'wvItem',item_type:'warehouseType',replenishment_status:'wvAttention',incoming:'whExpectedIncoming'}[key]||inventoryColumns.find(c=>c[0]===key)?.[1]||key);
export const warehouseQuantityKeys=['on_hand','reserved','available','projected','incoming','minimum_stock','maximum_stock','in_production','semi_finished'];
