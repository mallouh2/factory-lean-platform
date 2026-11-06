import {useState} from 'react';
import type {FeatureProps} from './types';
import {useSupply} from './useSupply';
import {historyNumber} from '@/utils/production-history-view.mjs';
export type InventoryExplanation={summary:{on_hand:string|null;reserved:string|null;available:string|null;projected:string|null;unit:string|null};rows:{id:string|null;quantity:string;kind:string;order_id:string|null;reference:string|null;status:string;purpose:string;sources:{label:string|null;quantity:string}[]}[];total:number;page:number;pages:number;known_reserved:string|null;unattributed_reserved:string;reconciled:boolean|null;difference:string|null;recent:Record<string,unknown>[]};
export default function WarehouseReservations({props,data,unit,busy,onPage}:{props:FeatureProps;data:InventoryExplanation;unit:string|null;busy:boolean;onPage:(page:number)=>void}){
 const {lang,t,can}=props,say=(en:string,ar:string)=>lang==='ar'?ar:en,[order,setOrder]=useState<{id:string;kind:string}|null>(null);
 const q=(v:unknown)=>(historyNumber(v,lang)??t('notAvailable'))+(unit?' '+t(unit):'');
 const purpose=(r:InventoryExplanation['rows'][number])=>r.kind==='SALES'?say('Sales fulfillment','تجهيز طلب مبيعات'):r.kind==='PRODUCTION'?say('Production materials','مواد للإنتاج'):r.kind==='UNATTRIBUTED'?say('Unattributed reserved balance','رصيد محجوز غير منسوب لطلب'):say('Material reservation','حجز مواد');
 return <section className="warehouse-reservations" aria-label={say('Reservation details','تفاصيل الحجز')}>
  <h4>{say('Reserved orders','الطلبات المحجوزة')}</h4>
  {data.reconciled===false&&<p role="alert">{say('Reservation records exceed the recorded balance. Ask Warehouse to review this discrepancy; no stock has been changed.','تتجاوز سجلات الحجز الرصيد المسجل. اطلب من المستودع مراجعة الفرق؛ لم يتغير المخزون.')}</p>}
  {data.reconciled===null&&<p>{say('A configured stock unit is required to explain this balance.','يلزم تحديد وحدة المخزون لتفسير هذا الرصيد.')}</p>}
  {data.pages>1&&<p className="warehouse-reservation-scope">{say('Showing','عرض')} {(data.page-1)*50+1}–{Math.min(data.page*50,data.total)} {say('of','من')} {data.total} · {say('The reserved total includes all pages.','إجمالي الحجز يشمل جميع الصفحات.')}</p>}
  {!data.rows.length&&data.reconciled!==null&&<p>{say('No recorded reservations for this stock unit.','لا توجد حجوزات مسجلة لوحدة المخزون هذه.')}</p>}
  {data.rows.map((r,i)=><article key={r.id||r.kind+i}><div><strong>{r.reference&&r.order_id&&(r.kind==='SALES'?can('sales_orders'):r.kind==='PRODUCTION'&&can('orders'))?<button type="button" onClick={()=>setOrder({id:r.order_id!,kind:r.kind})}><bdi>{r.reference}</bdi></button>:<bdi>{r.reference||purpose(r)}</bdi>}</strong><bdi className="warehouse-reserved-amount">{q(r.quantity)}</bdi></div><p>{purpose(r)} · {r.kind==='UNATTRIBUTED'?say('Recorded balance — order unknown','رصيد مسجل — الطلب غير معروف'):r.status==='cancelled'?say('Recorded reservation on a cancelled order','حجز مسجل لطلب ملغى'):say('Reserved','محجوز')}</p>{r.kind==='UNATTRIBUTED'&&<small>{say('No order attribution is present in the protected records. This quantity is not assigned to a guessed order.','لا تتضمن السجلات المحمية نسبة هذا الرصيد لطلب. لم يُنسب إلى طلب بالتخمين.')}</small>}{r.sources.length>0&&<details><summary>{say('Source details','تفاصيل المصدر')}</summary>{r.sources.map((s,j)=><p key={j}>{s.label||say('Unidentified source stock','مخزون مصدر غير محدد')} · {q(s.quantity)}</p>)}</details>}</article>)}
  {data.pages>1&&<nav aria-label={say('Reservation pages','صفحات الحجوزات')}><button disabled={busy||data.page<=1} onClick={()=>onPage(data.page-1)}>{t('previous')}</button><span>{data.page} / {data.pages}</span><button disabled={busy||data.page>=data.pages} onClick={()=>onPage(data.page+1)}>{t('next')}</button></nav>}
  {order&&<ReservationOrder props={props} order={order} onClose={()=>setOrder(null)}/>}
 </section>;
}
function ReservationOrder({props,order,onClose}:{props:FeatureProps;order:{id:string;kind:string};onClose:()=>void}){
 const {t,lang}=props,say=(en:string,ar:string)=>lang==='ar'?ar:en;
 const read=useSupply<Record<string,any>>(props.snapshot,'order',{item:order.id,kind:order.kind},true,'/api/warehouse-inventory');
 const r=read.data,q=(v:unknown,u:string)=>(historyNumber(v,lang)??t('notAvailable'))+' '+t(u);
 return <section className="warehouse-linked-order" aria-label={say('Reserved order','الطلب المرتبط بالحجز')}><button type="button" onClick={onClose}>{say('Back to reservations','العودة إلى الحجوزات')}</button>
  {read.loading&&<p role="status">{t('loading')}</p>}{read.error&&<p role="alert">{t(read.error)}</p>}
  {r&&<><h3><bdi>{r.code}</bdi></h3>{order.kind==='PRODUCTION'?<p>{lang==='ar'?r.product_name_ar||r.product_name:r.product_name} · {q(r.quantity,r.unit)}</p>:r.lines?.map((line:Record<string,any>)=><article key={line.id}><strong>{lang==='ar'?line.product_name_ar||line.product_name:line.product_name}</strong><p>{t('quantity')}: <bdi>{q(line.quantity,line.unit)}</bdi> · {say('Reserved','محجوز')}: <bdi>{q(line.reserved_quantity,line.unit)}</bdi> · {say('Dispatched','مرسل')}: <bdi>{q(line.dispatched_quantity,line.unit)}</bdi></p></article>)}</>}
 </section>;
}
