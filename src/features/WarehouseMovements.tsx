import OrderReference from '@/components/OrderReference';
import {useEffect,useState} from 'react';
import {Field,formatTime,localName} from '@/components/ui';
import TableExport from '@/components/TableExport';
import {WarehouseDialog,WarehousePicker} from './WarehouseUi';
import {useFulfillment} from './useFulfillment';
import {useSupply} from './useSupply';
import type{FeatureProps}from './types';
import type{InventoryRow}from './WarehouseInventory';
import type{MaterialStock}from './WarehouseReceiving';
import type{InventoryExplanation}from './WarehouseReservations';
import{decimalCompare}from '@/utils/quality-quantities.mjs';
import{historyNumber}from '@/utils/production-history-view.mjs';
export type WarehouseMovement={id:string;kind:string;quantity:unknown;reserved_delta?:unknown;unit?:string|null;created_at:unknown;actor_name?:string|null;note?:string|null;reference?:string|null;order_reference?:string|null};
export function MovementRow({props,movement:m,compact=false}:{props:FeatureProps;movement:WarehouseMovement;compact?:boolean}){
 const{t,lang,snapshot:s}=props,say=(en:string,ar:string)=>lang==='ar'?ar:en,sign=decimalCompare(String(m.quantity),'0'),reserved=m.reserved_delta!=null&&decimalCompare(String(m.reserved_delta),'0')!==0;
 const quantity=(v:unknown)=>(decimalCompare(String(v),'0')===1?'+':'')+(historyNumber(v,lang)??t('notAvailable'))+' '+t(m.unit||'historicalUnitUnknown');
 return <article className={'warehouse-movement-row '+(sign===1?'movement-in':sign===-1?'movement-out':'movement-neutral')}>
  <div className="warehouse-movement-main"><strong>{t('movement_'+m.kind)}</strong><bdi className="warehouse-movement-delta">{quantity(m.quantity)}</bdi></div>
  <div className="warehouse-movement-meta"><span>{sign===1?say('Stock in','وارد مخزون'):sign===-1?say('Stock out','صادر مخزون'):say('No physical stock change','دون تغيير المخزون الفعلي')}</span>{(m.order_reference||m.reference)&&<OrderReference reference={m.order_reference||m.reference}/>}<time>{formatTime(m.created_at,lang,String(s.factory?.timezone||'UTC'))}</time></div>
  {reserved&&<p className="warehouse-reservation-delta">{t('reservedMovementDelta')}: <bdi>{quantity(m.reserved_delta)}</bdi></p>}
  {!compact&&<>{m.actor_name&&<small>{t('receivingActor')}: {m.actor_name}</small>}{m.note&&<p dir="auto">{m.note}</p>}</>}
 </article>;
}
export default function WarehouseMovements(props:FeatureProps&{initialItem?:InventoryRow;materials?:MaterialStock[];onClose:()=>void;backToDetails?:boolean}){
 const{snapshot:s,t,lang,initialItem,can}=props,say=(en:string,ar:string)=>lang==='ar'?ar:en;
 const[type,setType]=useState(initialItem?.entity||'finished'),[item,setItem]=useState(initialItem?.id||''),[page,setPage]=useState(1);
 const products=s.tables.products.filter(p=>p.stage==='finished'),materials=props.materials||[];
 const options=(type==='finished'?products:materials).map(r=>({id:String(r.id),name:localName(r,lang)+(r.code?' · '+r.code:'')}));
 if(initialItem?.entity===type&&!options.some(p=>p.id===initialItem.id))options.push({id:initialItem.id,name:(lang==='ar'?initialItem.name_ar||initialItem.name:initialItem.name)+' · '+initialItem.code});
 const selected=options.find(p=>p.id===item),unit=initialItem?.id===item?initialItem.unit:type==='finished'?String(products.find(p=>p.id===item)?.stock_unit||''):materials.find(p=>p.id===item)?.unit||'';
 const read=useFulfillment<{rows:WarehouseMovement[];total:number}>(s,'movements',page,!!item&&can('warehouse'),{item,item_type:type});
 const context=useSupply<InventoryExplanation>(s,'context',{item,item_type:type,unit:unit||'',page:'1'},!!item&&!!unit&&can('warehouse'),'/api/warehouse-inventory');
 const pages=Math.max(1,Math.ceil((read.data?.total||0)/25));useEffect(()=>{if(read.data&&page>pages)setPage(pages);},[read.data,page,pages]);
 const references=new Map(context.data?.recent.map(m=>[m.id,m.order_reference]));
 return <WarehouseDialog {...props} drawer className="warehouse-movements-dialog" title={t('stockMovements')} onClose={props.onClose}>
  {props.backToDetails&&<button type="button" className="warehouse-back" onClick={props.onClose}>{say('Back to item details','العودة إلى تفاصيل الصنف')}</button>}
  <div className="warehouse-movement-filters"><Field label={t('inventoryType')}><select value={type} onChange={e=>{setType(e.target.value);setItem('');setPage(1);}}><option value="finished">{t('finishedProducts')}</option><option value="material">{t('materialInventory')}</option></select></Field><WarehousePicker label={t('product')} value={item} options={options} placeholder={t('wvSearch')} onChange={id=>{setItem(id);setPage(1);}}/></div>
  {!item&&<p className="warehouse-history-empty">{say('Choose an item to view its stock movements.','اختر صنفاً لعرض حركات مخزونه.')}</p>}
  {item&&<><div className="warehouse-movement-toolbar"><strong>{selected?.name}</strong><TableExport factory={String(s.factory?.id||'')} dataset="warehouse-movements" filters={{item,item_type:type}} total={read.data?.total??0} language={lang} t={t} disabled={!read.data||read.busy||!!read.error}/></div>
   {read.error&&<p role="alert">{t(read.error)} <button onClick={read.refresh}>{t('refresh')}</button></p>}{read.loading&&<p role="status">{t('loading')}</p>}
   <div className="warehouse-movement-results" aria-label={t('stockMovements')}>{read.data?.rows.map(m=><MovementRow key={m.id} props={props} movement={{...m,order_reference:String(references.get(m.id)||m.order_reference||'')||null}}/>)}</div>
   {read.data&&!read.data.rows.length&&<p>{t('noData')}</p>}
   <nav className="fulfillment-pagination"><button disabled={!read.data||page<=1||read.busy||!!read.error} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{say('Page','صفحة')} {page} / {pages}</span><button disabled={!read.data||page>=pages||read.busy||!!read.error} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
  </>}
 </WarehouseDialog>;
}
