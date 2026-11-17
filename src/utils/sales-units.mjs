import {decimalMultiply,quantityValid,decimalCompare} from './quality-quantities.mjs';
export function sellableProduct(p){return p?.stage==='finished'&&p.product_kind==='FINISHED_PRODUCT'&&!p.length_parent_id;}
export function salesUnits(p){if(!sellableProduct(p)||!['meter','piece'].includes(p.stock_unit))return [];return p.stock_unit==='meter'&&decimalCompare(p.unit_weight_kg,'0')===1?['meter','piece']:[p.stock_unit];}
export function cutLengthValid(value){return /^\d+(?:\.\d{1,6})?$/.test(String(value))&&decimalCompare(value,'0')===1&&decimalCompare(value,'1000')!==1;}
export function salesLineValid(line,p){return !!p&&salesUnits(p).includes(line.unit)&&quantityValid(line.quantity,line.unit)&&(line.unit!=='piece'||p.stock_unit!=='meter'||cutLengthValid(line.piece_length_m));}
export function totalPipeLength(count,length){return quantityValid(count,'piece')&&cutLengthValid(length)?decimalMultiply(count,length):null;}
