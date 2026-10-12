// Form previews only. PostgreSQL numeric and protected transactions are stock truth.
// Keep decimal strings through the new command boundary; do not round stock or kg.
function decimal(value) {
 const text=String(value??'').trim();
 if(text.length>2048)return null;
 const match=/^([+-]?)(?:(\d+)(?:\.(\d*))?|\.(\d+))(?:e([+-]?\d+))?$/i.exec(text);
 if(!match)return null;
 const exponent=Number(match[5]||0);if(!Number.isInteger(exponent)||Math.abs(exponent)>1000)return null;
 const fraction=match[3]??match[4]??'';
 let coefficient=BigInt((match[1]==='-'?'-':'')+(match[2]||'0')+fraction),scale=fraction.length-exponent;
 if(scale<0){coefficient*=10n**BigInt(-scale);scale=0;}
 while(scale>0&&coefficient%10n===0n){coefficient/=10n;scale--;}
 return {coefficient,scale};
}
function display({coefficient,scale}) {
 while(scale>0&&coefficient%10n===0n){coefficient/=10n;scale--;}
 const negative=coefficient<0n,raw=(negative?-coefficient:coefficient).toString().padStart(scale+1,'0');
 return (negative?'-':'')+(scale?raw.slice(0,-scale)+'.'+raw.slice(-scale):raw);
}
export function decimalCompare(left,right) {
 const a=decimal(left),b=decimal(right);if(!a||!b)return null;
 const scale=Math.max(a.scale,b.scale),difference=a.coefficient*10n**BigInt(scale-a.scale)-b.coefficient*10n**BigInt(scale-b.scale);
 return difference<0n?-1:difference>0n?1:0;
}
export function decimalMultiply(left,right) {
 const a=decimal(left),b=decimal(right);if(!a||!b)return null;
 return display({coefficient:a.coefficient*b.coefficient,scale:a.scale+b.scale});
}
export function decimalSubtract(left,right) {
 const a=decimal(left),b=decimal(right);if(!a||!b)return null;
 const scale=Math.max(a.scale,b.scale);
 return display({coefficient:a.coefficient*10n**BigInt(scale-a.scale)-b.coefficient*10n**BigInt(scale-b.scale),scale});
}
export function quantityValid(quantity,unit,available) {
 const amount=decimal(quantity);
 return !!amount&&amount.coefficient>0n&&['meter','piece','kg'].includes(unit)&&
  (unit!=='piece'||amount.scale===0)&&(available===undefined||decimalCompare(quantity,available)!==null&&decimalCompare(quantity,available)<=0);
}
export function scrapWeight(quantity,unit,weight,actual) {
 const defaultKg=quantityValid(quantity,unit)&&decimalCompare(weight,'0')===1?decimalMultiply(quantity,weight):null;
 return {defaultKg,actualKg:decimal(actual)?display(decimal(actual)):null,
  valid:quantityValid(quantity,unit)&&decimalCompare(actual,'0')===1,
  overridden:decimalCompare(actual,defaultKg)!==0};
}
