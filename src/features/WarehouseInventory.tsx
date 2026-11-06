import {projectedQuantity} from '@/utils/warehouse-presentation.mjs';
import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import type { FeatureProps } from './types';
import { Field } from '@/components/ui';
import {WarehouseDialog as Dialog} from './WarehouseUi';
import WarehouseItemDetails from './WarehouseItemDetails';
import {useTableDetails} from '@/components/useTableDetails';
import {defaultWarehouseColumns,visibleWarehouseColumns,warehousePreferenceKey,warehouseColumnTitle,warehouseQuantityKeys,warehouseColumnChoices} from '@/utils/warehouse-view.mjs';
import {historyNumber} from '@/utils/production-history-view.mjs';
import { useFulfillment } from './useFulfillment';
import { inventoryColumns, inventoryChoices, validInventoryFilters } from '@/utils/warehouse-inventory.mjs';
import { useSupplyCommand } from './useSupply';
import TableExport from '@/components/TableExport';
export type InventoryRow = {
 id:string; row_key:string; entity:string; name:string; name_ar:string; code:string; item_type:string; supply_source:string; unit:string|null;
 on_hand:number|null; reserved:number|null; available:number|null; incoming:number|null; projected:number|null; minimum_stock:number|null; maximum_stock:number|null;
 minimum_status:string; replenishment_status:string; can_produce:boolean; suggested_quantity:number|null; external_chosen:boolean;
 semi_finished?:number|null; in_production?:number|null; can_purchase?:boolean; unit_breakdown?:Array<Record<string,unknown>>;
};
type Filter = string | string[] | {op:string;value?:number;to?:number};
type Filters = Record<string,Filter>;
type Column = [string,string,string];
export default function WarehouseInventory(props:FeatureProps & {
 inventoryFilter?:ReactNode; onChanged:()=>void; revision?:number; inventoryType?:string; onConfigure:(row:InventoryRow)=>void; onReceive:(row:InventoryRow)=>void; onStoredUnfinished?:()=>void;
}) {
 const {snapshot:s,t,lang,can,command,onChanged,revision=0,onConfigure,onReceive}=props;
 const [scope,setScope]=useState(s.factory?.id),[filters,setFilters]=useState<Filters>({}),[page,setPage]=useState(1);
 useEffect(()=>{setFilters(old=>{const next={...old};if(props.inventoryType)next.item_type=props.inventoryType.split(',');else delete next.item_type;return next;});setPage(1);},[props.inventoryType]);
 const [sort,setSort]=useState('name'),[direction,setDirection]=useState('asc'),[filterColumn,setFilterColumn]=useState('');
 const [draft,setDraft]=useState<Filter>(''),[invalid,setInvalid]=useState(false);
 const [decision,setDecision]=useState<{row:InventoryRow;action:string}|null>(null),[quantity,setQuantity]=useState('');
 const [busy,setBusy]=useState(false),[notice,setNotice]=useState(''),[material,setMaterial]=useState<InventoryRow|null>(null);
 const [minimum,setMinimum]=useState(''),[maximum,setMaximum]=useState('');
 const [unitDetail,setUnitDetail]=useState<InventoryRow|null>(null);
 const purchasing=useSupplyCommand(command,s.factory?.id);
 const retry=useRef<{key:string;id:string}|null>(null), submitting=useRef(false);
 if(scope!==s.factory?.id){setScope(s.factory?.id);setFilters({});setPage(1);setDecision(null);setMaterial(null);}
 const read=useFulfillment<{rows:InventoryRow[];total:number;units:string[]}>(s,'inventory',page,can('warehouse'),
 {filters:JSON.stringify(scope===s.factory?.id?filters:{}),sort,direction,revision:String(revision)});
 const preferenceKey=warehousePreferenceKey(s.user?.id,s.factory?.id),[preference,setPreference]=useState<{scope:string|null;columns:string[]}>({scope:null,columns:defaultWarehouseColumns});
 const [selection,setSelection]=useState(''),[details,setDetails]=useState<InventoryRow|null>(null);
 const rowDetails=useTableDetails(),actionsId=useId(),columnsId=useId();
 useEffect(()=>{let value=defaultWarehouseColumns;if(preferenceKey)try{value=visibleWarehouseColumns(JSON.parse(localStorage.getItem(preferenceKey)||'null'));}catch{}setPreference({scope:preferenceKey,columns:value});setSelection('');setDetails(null);},[preferenceKey]);
 const shown=visibleWarehouseColumns(preference.scope===preferenceKey?preference.columns:null);
 function saveColumns(value:string[]){const columns=visibleWarehouseColumns(value);setPreference({scope:preferenceKey,columns});if(preferenceKey)try{localStorage.setItem(preferenceKey,JSON.stringify(columns));}catch{}}
 const allColumns=inventoryColumns.map(([key,title,kind])=>[key,['on_hand','reserved','available','projected','incoming'].includes(key)?warehouseColumnTitle(key):title,kind]) as Column[],columns=shown.map(key=>[key,warehouseColumnTitle(key),allColumns.find(c=>c[0]===key)![2]]) as Column[],active=Object.keys(filters);
 const selected=read.data?.rows.find(row=>row.row_key===selection),working=read.busy||!!read.error||busy||purchasing.busy;
 const title=(key:string)=>t(allColumns.find(c=>c[0]===key)![1]);
 const update=(key:string,value:Filter|undefined)=>{setFilters(old=>{const next={...old};if(value===undefined)delete next[key];else next[key]=value;return next;});setPage(1);};
 const openFilter=(key:string)=>{setFilterColumn(key);setDraft(filters[key]??(allColumns.find(c=>c[0]===key)?.[2]==='text'?'':allColumns.find(c=>c[0]===key)?.[2]==='set'?[]:{op:'eq'}));setInvalid(false);};
 const number=(value:unknown)=>historyNumber(value,lang)??t('notAvailable');
 const label=(key:string,value:string)=> key==='supply_source'?t('supply_'+value):key==='minimum_status'||key==='replenishment_status'?t(value==='INCOMING'?'whExpectedIncoming':'inventory_'+value):value==='NOT_CONFIGURED'?t('inventoryNotConfigured'):t(value);
 const cell=(row:InventoryRow,key:string)=>key==='name'?(lang==='ar'?row.name_ar||row.name:row.name):key==='code'?row.code:key==='projected'&&projectedQuantity(row.projected).shortage?t('whExpectedShortage')+': '+number(projectedQuantity(row.projected).quantity):
 ['item_type','supply_source','unit','minimum_status','replenishment_status'].includes(key)?label(key,String(row[key as keyof InventoryRow]??'NOT_CONFIGURED')):number(row[key as keyof InventoryRow] as number|null);
 async function run(name:string,args:Record<string,unknown>){
  if(submitting.current)return;submitting.current=true;setBusy(true);setNotice('');
  const key=JSON.stringify([name,args]);if(retry.current?.key!==key)retry.current={key,id:crypto.randomUUID()};
  try{await command(name,{factory:s.factory?.id,...args,...(name==='confirm_warehouse_replenishment'?{request_id:retry.current.id}:{})});
   retry.current=null;setDecision(null);setMaterial(null);setNotice('saved');read.refresh();onChanged();
  }catch(error){setNotice(error instanceof Error?error.message:'error');read.refresh();}
  finally{submitting.current=false;setBusy(false);}
 }
 const choose=(row:InventoryRow,action:string)=>{setDecision({row,action});setQuantity(row.suggested_quantity==null?'':String(row.suggested_quantity));setNotice('');};
 const actions=(row:InventoryRow)=>can('warehouse','edit')?<div className="inventory-actions">
 {(row.can_produce||(row.can_purchase&&row.supply_source==='BOTH')) && <button onClick={()=>choose(row,row.supply_source==='BOTH'?'choose':'produce')}>{t(row.supply_source==='BOTH'?'inventoryChooseSource':'inventoryCreateProduction')}</button>}
 {row.can_purchase&&row.supply_source==='EXTERNAL'&&<button onClick={()=>{choose(row,'purchase');purchasing.clearError();}}>{t('purchaseCreate')}</button>}
 {row.supply_source!=='MANUFACTURED'&&<button onClick={()=>onReceive(row)}>{t('receiveStock')}</button>}
 {row.entity==='material'?<button onClick={()=>{setMaterial(row);setMinimum(String(row.minimum_stock??''));setMaximum(String(row.maximum_stock??''));setNotice('');}}>{t('configureStock')}</button>:
 <button onClick={()=>onConfigure(row)}>{t('configureStock')}</button>}
 </div>:null;
 return <section className="warehouse-master" aria-label={t('inventoryCatalogue')} dir={lang==='ar'?'rtl':'ltr'}>
 <div className="warehouse-find-controls"><div className="wv-search"><Field label={t('wvSearch')}><input type="search" maxLength={200} value={typeof filters.name==='string'?filters.name:''} onChange={e=>update('name',e.target.value||undefined)}/></Field></div>{props.inventoryFilter}</div>
 <div className="warehouse-toolbar">
 <button popoverTarget={actionsId} disabled={!selected||working}>{t('historyActions')} ▾</button>
 <div id={actionsId} popover="auto" className="warehouse-popover" onClick={e=>{if((e.target as HTMLElement).closest('button'))e.currentTarget.hidePopover();}}>{selected&&<><button disabled={working} onClick={()=>setDetails(selected)}>{t('historyViewDetails')}</button>{actions(selected)}{Number(selected.semi_finished)>0&&props.onStoredUnfinished&&<button onClick={props.onStoredUnfinished}>{t('inventorySemiFinished')}</button>}</>}</div>
 <button popoverTarget={columnsId}>{t('historyColumns')} ▾</button>
 <div id={columnsId} popover="auto" className="warehouse-popover warehouse-columns">{warehouseColumnChoices.map(key=><label key={key}><input type="checkbox" checked={shown.includes(key)} disabled={shown.length===1&&shown.includes(key)} onChange={e=>saveColumns(e.target.checked?[...shown,key]:shown.filter(k=>k!==key))}/>{t(warehouseColumnTitle(key))}</label>)}<button onClick={()=>saveColumns(defaultWarehouseColumns)}>{t('historyRestoreColumns')}</button></div>
 <button onClick={()=>openFilter('item_type')}>{t('inventoryFilters')}{active.length?' · '+active.length:''}</button>
 {active.length>0&&<button onClick={()=>{setFilters({});setPage(1);}}>{t('inventoryClearAll')}</button>}
 {can('warehouse')&&<TableExport factory={String(s.factory?.id||'')} dataset="warehouse-stock" filters={scope===s.factory?.id?filters:{}} sort={sort} direction={direction} total={read.data?.total??0} language={lang} t={t} disabled={read.busy||!read.data||!!read.error}/>}
 </div>
 {(read.error||notice)&&<p role="status">{t(read.error||notice)}</p>}{read.loading&&<p role="status">{t('loading')}</p>}
 {read.data?.rows.length===0&&<p className="empty">{t('noResults')}</p>}
 <p className="muted wv-table-help">{t('wvTableHelp')}</p>
 <div className="inventory-table-scroll" role="region" aria-label={t('inventoryCatalogue')} tabIndex={0}><table className="inventory-table"><thead><tr>{columns.map(([key,label])=><th key={key} scope="col" aria-sort={sort===key?(direction==='asc'?'ascending':'descending'):'none'}><div><button onClick={()=>{setSort(key);setDirection(sort===key&&direction==='asc'?'desc':'asc');setPage(1);}}>{t(label)} {sort===key?(direction==='asc'?'↑':'↓'):''}</button></div></th>)}</tr></thead>
 <tbody>{read.data?.rows.map(row=><tr key={row.row_key} tabIndex={0} aria-selected={selection===row.row_key} data-low={row.minimum_status==='AT_OR_BELOW_MIN'} {...rowDetails(()=>setSelection(row.row_key),()=>setDetails(row),working)}>{columns.map(([key,label])=><td key={key} data-label={t(label)} data-stock-kind={warehouseQuantityKeys.includes(key)?key:undefined}>{key==='name'?<><strong>{cell(row,key)}</strong><small><bdi>{row.code}</bdi></small></>:key==='replenishment_status'?<span className={row.minimum_status==='AT_OR_BELOW_MIN'||!row.unit?'wv-warning':''}>{!row.unit?t('wvUnknownUnit'):row.replenishment_status==='OK'?'—':cell(row,key)}</span>:warehouseQuantityKeys.includes(key)?<span className={'warehouse-quantity warehouse-quantity-'+key+(Number(row[key as keyof InventoryRow])<0?' is-negative':'')}>{key==='reserved'?<button type="button" onClick={e=>{e.stopPropagation();setDetails(row);}}><bdi>{cell(row,key)}{row[key as keyof InventoryRow]!=null&&row.unit?' '+t(row.unit):''}</bdi></button>:<bdi>{cell(row,key)}{row[key as keyof InventoryRow]!=null&&row.unit?' '+t(row.unit):''}</bdi>}</span>:cell(row,key)}</td>)}</tr>)}</tbody></table></div>
 <nav className="fulfillment-pagination" aria-label={t('inventoryCatalogue')}><button disabled={page===1||read.busy} onClick={()=>setPage(p=>p-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total??0)} onClick={()=>setPage(p=>p+1)}>{t('next')}</button></nav>
 {details&&<WarehouseItemDetails {...props} key={details.row_key} row={read.data?.rows.find(r=>r.row_key===details.row_key)||details} onClose={()=>setDetails(null)}/>}
 {filterColumn&&<Dialog {...props} title={t('inventoryFilters')} t={t} onClose={()=>setFilterColumn('')}>
 <Field label={t('inventoryColumn')}><select value={filterColumn} onChange={e=>openFilter(e.target.value)}>{allColumns.map(([key,title])=><option value={key} key={key}>{t(title)}</option>)}</select></Field>
 {allColumns.find(c=>c[0]===filterColumn)![2]==='text'?<Field label={t('inventoryContains')}><input maxLength={200} value={typeof draft==='string'?draft:''} onChange={e=>setDraft(e.target.value)}/></Field>:
 allColumns.find(c=>c[0]===filterColumn)![2]==='set'?<fieldset className="inventory-options"><legend>{t(allColumns.find(c=>c[0]===filterColumn)![1])}</legend>
 {(filterColumn==='unit'?read.data?.units??[]:inventoryChoices[filterColumn as keyof typeof inventoryChoices]??[]).map((value:string)=><label key={value}><input type="checkbox" checked={Array.isArray(draft)&&draft.includes(value)} onChange={e=>setDraft(old=>e.target.checked?[...(Array.isArray(old)?old:[]),value]:(Array.isArray(old)?old:[]).filter(v=>v!==value))}/>{label(filterColumn,value)}</label>)}</fieldset>:
 <><Field label={t('inventoryCondition')}><select value={typeof draft==='object'&&!Array.isArray(draft)?draft.op:'eq'} onChange={e=>setDraft({op:e.target.value})}>{['eq','gt','lt','range','positive','configured','not_configured'].map(v=><option key={v} value={v}>{t('inventoryOp_'+v)}</option>)}</select></Field>
 {typeof draft==='object'&&!Array.isArray(draft)&&['eq','gt','lt','range'].includes(draft.op)&&<>
 <Field label={t('quantity')}><input type="number" step="any" value={draft.value??''} onChange={e=>setDraft({...draft,value:e.target.value===''?undefined:Number(e.target.value)})}/></Field>
 {draft.op==='range'&&<Field label={t('inventoryRangeEnd')}><input type="number" step="any" value={draft.to??''} onChange={e=>setDraft({...draft,to:e.target.value===''?undefined:Number(e.target.value)})}/></Field>}</>}</>}
 {invalid&&<p role="alert">{t('fulfillmentInvalid')}</p>}
 <div className="row-actions"><button onClick={()=>{update(filterColumn,undefined);setFilterColumn('');}}>{t('inventoryClearFilter')}</button>
 <button className="primary" onClick={()=>{if(!validInventoryFilters({[filterColumn]:draft})){setInvalid(true);return;}update(filterColumn,draft===''||(Array.isArray(draft)&&!draft.length)?undefined:draft);setFilterColumn('');}}>{t('inventoryApply')}</button></div></Dialog>}
 {decision&&<Dialog {...props} title={t(decision.action==='choose'?'inventoryChooseSource':decision.action==='purchase'?'purchaseConfirm':'inventoryConfirmProduction')} t={t} onClose={()=>{if(!busy&&!purchasing.busy)setDecision(null);}}>
 <strong>{cell(decision.row,'name')}</strong>
 {decision.action==='choose'?<div className="row-actions"><button onClick={()=>choose(decision.row,'produce')}>{t('inventoryProduceInternally')}</button><button onClick={()=>{choose(decision.row,'purchase');purchasing.clearError();}}>{t('inventoryPurchaseExternally')}</button></div>:decision.action==='purchase'?<form onSubmit={async e=>{e.preventDefault();if(await purchasing.run('purchase_stock',{item:decision.row.id,unit:decision.row.unit,projected:decision.row.projected,quantity:Number(quantity)})){setDecision(null);read.refresh();onChanged();}}}><fieldset disabled={purchasing.busy}>
 <dl className="inventory-confirm-values">{['on_hand','projected','minimum_stock','maximum_stock'].map(key=><div key={key}><dt>{key==='projected'&&projectedQuantity(decision.row.projected).shortage?t('whExpectedShortage'):title(key)}</dt><dd>{key==='projected'?number(projectedQuantity(decision.row.projected).quantity):cell(decision.row,key)} {cell(decision.row,'unit')}</dd></div>)}</dl>
 <Field label={t('inventorySuggested')}><input required type="number" min="0.000001" step="any" value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>{decision.row.suggested_quantity==null&&<p>{t('inventoryMissingMax')}</p>}
 {purchasing.error&&<p role="alert">{t(purchasing.error)}</p>}<div className="row-actions"><button type="button" onClick={()=>setDecision(null)}>{t('cancel')}</button><button className="primary" disabled={purchasing.busy||Number(quantity)<=0}>{t('purchaseConfirm')}</button></div></fieldset></form>:
 <form onSubmit={e=>{e.preventDefault();void run('confirm_warehouse_replenishment',{product:decision.row.id,action:'produce',unit:decision.row.unit,projected:decision.row.projected,quantity:Number(quantity)});}}><fieldset disabled={busy}>
 <dl className="inventory-confirm-values">{['on_hand','projected','minimum_stock','maximum_stock'].map(key=><div key={key}><dt>{key==='projected'&&projectedQuantity(decision.row.projected).shortage?t('whExpectedShortage'):title(key)}</dt><dd>{key==='projected'?number(projectedQuantity(decision.row.projected).quantity):cell(decision.row,key)} {cell(decision.row,'unit')}</dd></div>)}</dl>
 <Field label={t('inventorySuggested')}><input required type="number" min="0.000001" step="any" readOnly={decision.row.suggested_quantity!=null} value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
 {decision.row.suggested_quantity==null&&<p>{t('inventoryMissingMax')}</p>}<p>{t('inventoryConfirmationHelp')}</p>
 <div className="row-actions"><button type="button" disabled={busy} onClick={()=>setDecision(null)}>{t('cancel')}</button><button className="primary" disabled={busy||!quantity||Number(quantity)<=0}>{t('inventoryConfirmProduction')}</button></div>
 </fieldset></form>}{notice&&<p role="alert">{t(notice)}</p>}</Dialog>}
 {material&&<Dialog {...props} title={t('configureStock')} t={t} onClose={()=>{if(!busy)setMaterial(null);}}><strong>{cell(material,'name')}</strong><form onSubmit={e=>{e.preventDefault();void run('configure_warehouse_material',{material:material.id,minimum:minimum===''?null:Number(minimum),maximum:maximum===''?null:Number(maximum)});}}><fieldset disabled={busy}>
 <Field label={t('stockMin')}><input type="number" min="0" step="any" value={minimum} onChange={e=>setMinimum(e.target.value)}/></Field><Field label={t('stockMax')}><input type="number" min={Number(minimum)||0.000001} step="any" value={maximum} onChange={e=>setMaximum(e.target.value)}/></Field>
 {notice&&<p role="alert">{t(notice)}</p>}<button className="primary">{t('save')}</button></fieldset></form></Dialog>}
 {unitDetail&&<Dialog {...props} title={t('inventoryUnitBreakdown')} t={t} onClose={()=>setUnitDetail(null)}><strong>{cell(unitDetail,'name')}</strong><p>{t('inventoryUnitBreakdownHelp')}</p><ul>{unitDetail.unit_breakdown?.map(row=><li key={String(row.unit)}>{t(String(row.unit||'inventoryNotConfigured'))}: {t('stock_on_hand')} {number((row.on_hand??0) as number)} · {t('stock_reserved')} {number((row.reserved??0) as number)} · {t(projectedQuantity(row.projected).shortage?'whExpectedShortage':'whProjected')} {number(projectedQuantity(row.projected).quantity)} · {t('inventorySemiFinished')} {number((row.semi_finished??0) as number)}</li>)}</ul></Dialog>}
 </section>;
}
