import {useEffect,useState} from 'react';
import type {FeatureProps} from './types';
import {useFulfillment} from './useFulfillment';
import {WarehouseDialog} from './WarehouseUi';
import TableExport from '@/components/TableExport';
export type StoredUnfinished={row_key:string;product_id:string;name:string;name_ar:string;unit:string;missing_operations:{id:string;name:string;name_ar?:string}[];restriction:string;classification_available:boolean;on_hand:string;reserved:string;available:string;held:boolean};
export default function StoredUnfinishedInventory(props:FeatureProps){
 const {snapshot:s,t,lang,can}=props,say=(en:string,ar:string)=>lang==='ar'?ar:en;
 const [page,setPage]=useState(1),[search,setSearch]=useState(''),[selected,setSelected]=useState<StoredUnfinished|null>(null),[details,setDetails]=useState(false),[columns,setColumns]=useState(['product','type','operations','unit','on_hand','reserved','available','status']);
 const read=useFulfillment<{rows:StoredUnfinished[];total:number;classification_unavailable:number}>(s,'stored_wip',page,can('warehouse'));
 const key=`factory-lean:stored-wip-columns:${s.user.id}:${s.factory?.id}`;
 const labels:Record<string,string>={product:t('product'),type:say('Type','النوع'),operations:say('Missing operations','العمليات المتبقية'),unit:t('unit'),on_hand:t('stock_on_hand'),reserved:t('stock_reserved'),available:t('stock_available'),status:t('status')};
 const operations=(r:StoredUnfinished)=>r.classification_available?r.missing_operations.map(o=>lang==='ar'?o.name_ar||o.name:o.name).join(' + '):say('Classification unavailable','التصنيف غير متاح');
 useEffect(()=>{setSelected(null);setDetails(false);try{const saved=JSON.parse(localStorage.getItem(key)||'null');if(Array.isArray(saved)&&saved.every(v=>Object.hasOwn(labels,v)))setColumns([...new Set(['product','unit','status',...saved])]);}catch{}},[key]);
 useEffect(()=>{if(read.data?.classification_unavailable)console.warn('warehouse_classification_unavailable',{count:read.data.classification_unavailable});},[read.data]);
 const rows=read.data?.rows.filter(r=>[r.name,r.name_ar,operations(r)].some(v=>v?.toLocaleLowerCase().includes(search.toLocaleLowerCase())))||[];
 const cell=(r:StoredUnfinished,k:string)=>k==='product'?(lang==='ar'?r.name_ar||r.name:r.name):k==='type'?say('Unfinished','غير مكتمل'):k==='operations'?operations(r):k==='unit'?t(r.unit):k==='status'?(r.held?say('Quality hold','إيقاف من الجودة'):'—'):`${r[k as 'on_hand'|'reserved'|'available']} ${t(r.unit)}`;
 return <section className="stored-unfinished-inventory">
 <p>{say('Stored unfinished stock is not finished stock. Reserved quantities belong to recovery work.','الإنتاج غير المكتمل المخزن ليس مخزوناً مكتملاً. الكميات المحجوزة مخصصة لأعمال الإكمال.')}</p>
 <div className="table-toolbar"><label>{say('Search displayed classifications','بحث التصنيفات المعروضة')}<input type="search" value={search} maxLength={200} onChange={e=>setSearch(e.target.value)}/></label>
 <details><summary>{t('historyColumns')}</summary>{Object.entries(labels).map(([id,label])=><label key={id}><input type="checkbox" checked={columns.includes(id)} disabled={['product','unit','status'].includes(id)} onChange={e=>{const next=e.target.checked?[...columns,id]:columns.filter(v=>v!==id);setColumns(next);try{localStorage.setItem(key,JSON.stringify(next));}catch{}}}/>{label}</label>)}</details>
 <button disabled={!selected} onClick={()=>setDetails(true)}>{t('historyViewDetails')}</button>
 <TableExport factory={String(s.factory?.id)} dataset="warehouse-stored-wip" filters={{}} total={read.data?.total||0} language={lang} t={t} showScope={false} disabled={read.busy||!read.data||!!read.error}/><small>{say('Export includes all stored classifications.','يشمل التصدير جميع التصنيفات المخزنة.')}</small>
 </div>
 {read.error&&<p role="alert">{t(read.error)} <button onClick={read.refresh}>{t('refresh')}</button></p>}{read.loading&&<p role="status">{t('loading')}</p>}
 <div className="table-wrap"><table><thead><tr>{columns.map(k=><th key={k}>{labels[k]}</th>)}</tr></thead><tbody>{rows.map(r=><tr key={r.row_key} aria-selected={selected?.row_key===r.row_key} onClick={()=>setSelected(r)} onDoubleClick={()=>{setSelected(r);setDetails(true);}}>{columns.map(k=><td key={k} data-label={labels[k]}>{k==='product'?<button onClick={()=>{setSelected(r);setDetails(true);}}>{cell(r,k)}</button>:cell(r,k)}</td>)}</tr>)}</tbody></table></div>
 {read.data&&!rows.length&&<p role="status">{t('noResults')}</p>}
 <nav><button disabled={page===1||read.busy} onClick={()=>setPage(n=>n-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(n=>n+1)}>{t('next')}</button></nav>
 {details&&selected&&<WarehouseDialog {...props} drawer title={t('historyViewDetails')} onClose={()=>setDetails(false)}><h3>{cell(selected,'product')}</h3><p>{operations(selected)}</p>{selected.restriction&&<p dir="auto">{selected.restriction}</p>}<dl className="wv-values">{['on_hand','reserved','available'].map(k=><div key={k}><dt>{labels[k]}</dt><dd>{cell(selected,k)}</dd></div>)}</dl>{selected.held&&<p role="alert">{say('Quality reconciliation must be completed before allocating this stock.','يجب إكمال تسوية الجودة قبل تخصيص هذا المخزون.')}</p>}</WarehouseDialog>}
 </section>;
}
