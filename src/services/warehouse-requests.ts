import en from '@/locales/en.json';
import ar from '@/locales/ar.json';
import {warehouseRequestRows,warehouseRequestLabels} from '@/utils/warehouse-request-rows.mjs';
import type {authenticatedClient} from './authorization';
type Client=Awaited<ReturnType<typeof authenticatedClient>>['db'];
type Row=Record<string,any>;
export const warehouseRequestPageSize=50;
// Existing protected sources have different page sizes and include ineligible
// rows. Exhaust their actual counts before filtering/paging the combined queue.
// A bounded/incomplete scan fails closed; it never invents a next page.
export async function warehouseRequestsPage(db:Client,factory:string,filters:{page:number;kind:string;search:string;language:'en'|'ar'},signal?:AbortSignal){
 const rpc=async(name:string,args:Row)=>{if(signal?.aborted)throw Error('tableExportCancelled');const r=await db.rpc(name,args);if(r.error)throw r.error;return r.data;};
 async function counted(name:string,args:Row,key='rows',count='total'){
  const rows:Row[]=[];let total:number|undefined;
  for(let page=1;page<=200;page++){
   const d=await rpc(name,{factory,...args,page}),n=d?.[count],batch=d?.[key];
   if(!Number.isSafeInteger(n)||n<0||n>10000||!Array.isArray(batch)||(total!==undefined&&total!==n))throw Error('tableExportChanged');
   total=n;rows.push(...batch);if(rows.length>n||(!batch.length&&rows.length<n))throw Error('tableExportChanged');
   if(rows.length===n){if(new Set(rows.map(r=>r.id)).size!==rows.length)throw Error('tableExportChanged');return rows;}
  }throw Error('tableExportExcelLimit');
 }
 async function receiving(){const rows:Row[]=[];for(let page=0;page<=200;page++){
  const d=await rpc('manufactured_receiving_read',{factory,page});if(!Array.isArray(d?.rows)||typeof d.has_more!=='boolean'){
   if(d?.available===false&&Array.isArray(d.rows)&&!d.rows.length)return [];
   throw Error('tableExportChanged');
  }rows.push(...d.rows);if(rows.length>10000)throw Error('tableExportExcelLimit');
  if(!d.has_more){if(new Set(rows.map(r=>r.id)).size!==rows.length)throw Error('tableExportChanged');return rows;}
  if(!d.rows.length)throw Error('tableExportChanged');
 }throw Error('tableExportExcelLimit');}
 const [materials,receipts,legacy,orders]=await Promise.all([
  !filters.kind||['issue','unfinished'].includes(filters.kind)?counted('supply_page',{mode:'materials'}):[],
  !filters.kind||filters.kind==='receipt'?receiving():[],
  !filters.kind||filters.kind==='acknowledge'?counted('supply_page',{mode:'outputs'}):[],
  !filters.kind||filters.kind==='dispatch'?counted('warehouse_dispatch_requests_page',{},'orders','orders_total'):[]]);
 const words:Record<string,string>=filters.language==='ar'?ar:en,t=(key:string)=>words[key]||key,labels=warehouseRequestLabels(filters.language);
 const matched=warehouseRequestRows({materials,receipts,legacy,orders,lang:filters.language,t}).filter(r=>(!filters.kind||r.kind===filters.kind)&&[r.reference,r.name,labels[r.kind as keyof typeof labels]].some(v=>v.toLocaleLowerCase().includes(filters.search.toLocaleLowerCase())));
 const total=matched.length,pages=Math.max(1,Math.ceil(total/warehouseRequestPageSize)),page=Math.min(filters.page,pages),rows=matched.slice((page-1)*warehouseRequestPageSize,page*warehouseRequestPageSize);
 const pools:Row[]=[];const visibleOrders=[...new Set(rows.filter(r=>r.kind==='dispatch').map(r=>r.order!.id))];
 for(let i=0;i<visibleOrders.length;i+=5){const group=await Promise.all(visibleOrders.slice(i,i+5).map(id=>rpc('pooled_dispatch_context',{factory,sales_order:id})));pools.push(...group.flatMap(d=>d.rows||[]));}
 const available=Object.fromEntries(pools.map(r=>[r.id,r.dispatchable]));
 const items=[...new Set(rows.filter(r=>r.material?.production_item_id&&r.material.item_type!=='lot').map(r=>String(r.material!.production_item_id)))];
 const progress:Row[]=[];for(let i=0;i<items.length;i+=5){const batch=await Promise.all(items.slice(i,i+5).map(item=>rpc('production_material_work',{factory,audience:'WAREHOUSE',item})));progress.push(...batch.flatMap(d=>d.rows||[]));}const byId=new Map(progress.map(r=>[r.id,r]));
 return {rows:rows.map(r=>{const p=byId.get(r.id);return r.kind==='dispatch'?{...r,available:available[r.id]??'—'}:p?.managed?{...r,status:t('materialState_'+p.state),available:p.available??'—'}:r;}),total,page,pages,page_size:warehouseRequestPageSize,has_more:page<pages};
}
