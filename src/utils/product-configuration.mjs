const object=x=>!!x&&typeof x==='object'&&!Array.isArray(x);
const uuid=x=>typeof x==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(x);
const number=x=>(typeof x==='number'||typeof x==='string'&&/^\d+(\.\d+)?$/.test(x))&&Number.isFinite(Number(x));
const positive=x=>number(x)&&Number(x)>0;
export function stockUnitWeight({basis,weight,length,stockUnit}){
 if(!positive(weight)||!['STOCK_UNIT','PIECE'].includes(basis))return null;
 if(stockUnit==='kg')return 1;
 if(!['meter','piece'].includes(stockUnit))return null;
 if(basis==='PIECE'&&stockUnit==='meter')return positive(length)?Number(weight)/Number(length):null;
 return Number(weight);
}
export function validProductConfiguration(a){
 if(!object(a)||Object.keys(a).some(k=>!['factory','product','payload','recipe','lines','fingerprint','request_id'].includes(k))||!uuid(a.factory)||!(a.product===null||uuid(a.product))||!uuid(a.request_id)||!/^[a-f0-9]{64}$/.test(a.fingerprint)||!object(a.payload)||!object(a.recipe)||JSON.stringify(a).length>100000)return false;
 if(Object.keys(a.payload).some(k=>!['name','name_ar','code','category','unit','diameter','length','color','weight','standard_rate','stage','product_kind','stock_unit','unit_weight_kg','weight_basis'].includes(k)))return false;
 const r=a.recipe;
 if(!['KEEP','DRAFT','EXISTING','INLINE'].includes(r.mode)||Object.keys(r).some(k=>!['mode','formula','components','reuse','name','input_mode','batch_quantity'].includes(k))||r.batch_quantity!=null&&!positive(r.batch_quantity))return false;
 if(r.mode==='EXISTING'&&!uuid(r.formula))return false;
 if(r.mode==='INLINE'&&(!Array.isArray(r.components)||!r.components.length||r.components.length>100||r.components.some(c=>!object(c)||Object.keys(c).some(k=>!['material_id','quantity','unit','waste_allowance'].includes(k))||!uuid(c.material_id)||!positive(c.quantity)||c.unit!=='kg'||c.waste_allowance!=null&&(!number(c.waste_allowance)||Number(c.waste_allowance)<0))||new Set(r.components.map(c=>c.material_id)).size!==r.components.length))return false;
 return a.lines===null||Array.isArray(a.lines)&&a.lines.length<=1000&&new Set(a.lines.map(l=>l.line)).size===a.lines.length&&a.lines.every(l=>object(l)&&Object.keys(l).every(k=>['line','rate','machines'].includes(k))&&uuid(l.line)&&positive(l.rate)&&Array.isArray(l.machines)&&l.machines.length>0&&l.machines.every(uuid)&&new Set(l.machines).size===l.machines.length);
}
export async function submitProductConfiguration(intent,fetcher=fetch){
 try{
  const r=await fetcher('/api/product-configuration',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(intent),signal:AbortSignal.timeout(25000)}),b=await r.json();
  if(r.ok&&uuid(b.id))return {outcome:'COMMITTED',id:b.id};
  if(r.status>=400&&r.status<500&&typeof b.error==='string')return {outcome:'REJECTED',error:b.error};
 }catch{/* An unknown result must retain its original request identity. */}
 return recoverProductConfiguration(intent,fetcher);
}
export async function recoverProductConfiguration(intent,fetcher=fetch){
 try{const r=await fetcher('/api/product-configuration?'+new URLSearchParams({factory:intent.factory,request_id:intent.request_id}),{cache:'no-store'}),b=await r.json();const {factory,request_id,...expected}=intent;
  const canonical=x=>JSON.stringify(x,(_k,v)=>object(v)?Object.fromEntries(Object.keys(v).sort().map(k=>[k,v[k]])):v);
  if(r.ok&&b.receipt?.request_id===request_id&&uuid(b.receipt.id)&&canonical(b.receipt.intent)===canonical(expected))return {outcome:'COMMITTED',id:b.receipt.id};
 }catch{/* Missing or unreadable receipts do not prove failure. */}
 return {outcome:'UNKNOWN',error:'f45SaveUnknown'};
}
