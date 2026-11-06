import {decimalCompare,decimalSubtract} from './quality-quantities.mjs';
export function projectedQuantity(value){
 if(value==null)return{shortage:false,quantity:null};
 const shortage=decimalCompare(String(value),'0')===-1;
 return{shortage,quantity:shortage?decimalSubtract('0',String(value)):String(value)};
}
// Display breakdown only: mirrors the existing protected row's formula. Never posts stock.
export function warehouseForecast(row){
 const available=row.available,incoming=row.incoming,active=row.entity==='material'?'0':row.in_production;
 if(!row.unit||[available,incoming,active,row.projected].some(v=>v==null||decimalCompare(String(v),'0')===null))return null;
 const supply=decimalSubtract(decimalSubtract(String(available),decimalSubtract('0',String(incoming))),decimalSubtract('0',String(active)));
 const demand=decimalSubtract(supply,String(row.projected));
 if(decimalCompare(demand,'0')===-1)return null;
 return{incoming:String(incoming),active:String(active),demand,projected:String(row.projected)};
}
