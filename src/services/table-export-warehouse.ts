import {warehouseRequestsPage} from './warehouse-requests';
import en from '@/locales/en.json';
import ar from '@/locales/ar.json';
import {warehouseRequestLabels} from '@/utils/warehouse-request-rows.mjs';
import type {authenticatedClient} from './authorization';
type Client=Awaited<ReturnType<typeof authenticatedClient>>['db'];
type Row=Record<string,any>;
export async function warehouseRequestExportRows(db:Client,factory:string,filters:Row,language:'en'|'ar'){
 return (await warehouseRequestsPage(db,factory,{page:filters.department_page,kind:filters.kind,search:filters.search,status:filters.status||'active',language})).rows;
}
export function warehouseSupplementReport(dataset:string,language:'en'|'ar',rows:Row[]){
 const words:Record<string,string>=language==='ar'?ar:en,t=(key:string)=>words[key]||key,say=(a:string,b:string)=>language==='ar'?b:a;
 const requests=dataset==='warehouse-requests',labels=warehouseRequestLabels(language);
 const columns=requests?[['reference',say('Request reference','مرجع الطلب')],['kind',say('Request type','نوع الطلب')],['department',say('Department','القسم')],['name',t('product')],['quantity',t('quantity')],['unit',t('unit')],['available',t('available')],['status',t('status')]]:
  [['name',t('product')],['type',say('Type','النوع')],['operations',say('Missing operations','العمليات المتبقية')],['unit',t('unit')],['on_hand',t('stock_on_hand')],['reserved',t('stock_reserved')],['available',t('stock_available')],['status',t('status')]];
 return{title:requests?say('Warehouse Requests','طلبات المستودع'):say('Stored Unfinished / WIP','إنتاج غير مكتمل مخزن'),columns:columns.map(([key,label])=>({key,label,width:24})),rows:rows.map(r=>requests?{...r,kind:labels[r.kind as keyof typeof labels],unit:t(r.unit)}:{...r,name:language==='ar'?r.name_ar||r.name:r.name,type:say('Unfinished','غير مكتمل'),operations:r.classification_available?r.missing_operations.map((o:Row)=>language==='ar'?o.name_ar||o.name:o.name).join(' + '):say('Classification unavailable','التصنيف غير متاح'),unit:t(r.unit),status:r.held?say('Quality hold','إيقاف من الجودة'):'—'}),t};
}
