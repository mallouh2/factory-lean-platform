import { useState } from 'react';
import { Dialog, Field } from '@/components/ui';
import type { FeatureProps } from './types';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';

export default function WarehousePurchase(props: FeatureProps & { onClose:()=>void; onChanged:()=>void }) {
 const {snapshot:s,t,lang,onClose,onChanged}=props;
 const [search,setSearch]=useState(''),[page,setPage]=useState(1),[choice,setChoice]=useState<SupplyRow|null>(null);
 const [unit,setUnit]=useState('piece'),[quantity,setQuantity]=useState(''),[details,setDetails]=useState('');
 const [open,setOpen]=useState(false),[active,setActive]=useState(-1);
 const read=useSupply(s,'catalogue',{page:String(page),filters:JSON.stringify({search})});
 const action=useSupplyCommand(props.command,s.factory?.id);
 const other=choice?.id==='other';
 const name=(row:SupplyRow)=>row.id==='other'?t('purchaseOther'):String(lang==='ar'?row.name_ar||row.name:row.name);
 const options=[...(read.data?.rows||[]),{id:'other',name:t('purchaseOther')}];
 const units=other?['piece','kg','meter']:choice?.unit?[String(choice.unit)]:choice?.item_type==='MANUFACTURED_INTERMEDIATE'?['kg']:['piece','meter'];
 function choose(row:SupplyRow){setChoice(row);setSearch('');setPage(1);setOpen(false);setActive(-1);setUnit(String(row.unit||(row.item_type==='MANUFACTURED_INTERMEDIATE'?'kg':'piece')));}
 return <Dialog title={t('purchaseCreate')} t={t} onClose={()=>{if(!action.busy)onClose();}}>
  <form onSubmit={async e=>{e.preventDefault();if(!choice||!props.can('warehouse','edit')||(other&&!details.trim()))return;
   if(await action.run('purchase_inventory',{item:choice.id,unit,quantity:Number(quantity),details:details.trim()})){onChanged();onClose();}
  }}><fieldset disabled={action.busy} className="fulfillment-form">
   <Field label={t('item')}><div className="orders-v2-product-combobox warehouse-purchase-item">
    <input role="combobox" required autoComplete="off" value={search||(choice?name(choice):'')} placeholder={t('purchaseItemSearch')}
     aria-autocomplete="list" aria-expanded={open} aria-controls="warehouse-purchase-options"
     aria-activedescendant={open&&active>=0&&options[active]?'warehouse-purchase-option-'+String(options[active].id):undefined}
     onFocus={()=>{setSearch('');setPage(1);setOpen(true);setActive(-1);}}
     onBlur={()=>{setOpen(false);setActive(-1);}}
     onChange={e=>{setSearch(e.target.value);setPage(1);setChoice(null);setUnit('piece');setOpen(true);setActive(-1);}}
     onKeyDown={e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);setActive(e.key==='ArrowDown'?(active+1)%options.length:(active+options.length-1)%options.length);}
      else if(e.key==='PageDown'&&open&&page*50<(read.data?.total||0)){e.preventDefault();setPage(p=>p+1);setActive(-1);}
      else if(e.key==='PageUp'&&open&&page>1){e.preventDefault();setPage(p=>p-1);setActive(-1);}
      else if(e.key==='Enter'&&open){e.preventDefault();if(active>=0&&options[active])choose(options[active]);}
      else if(e.key==='Escape'&&open){e.preventDefault();setOpen(false);setActive(-1);}}}/>
    <span className="orders-v2-product-caret" aria-hidden="true">⌄</span>
    {open&&<div className="warehouse-purchase-options"><ul id="warehouse-purchase-options" className="orders-v2-product-options" role="listbox" aria-label={t('item')}>
     {!read.busy&&!read.data?.rows.length&&<li role="presentation">{t('noResults')}</li>}
     {options.map((row,index)=><li key={String(row.id)} id={'warehouse-purchase-option-'+String(row.id)} role="option" aria-selected={row.id===choice?.id}
      className={index===active?'is-active':''} onPointerDown={e=>e.preventDefault()} onClick={()=>choose(row)}>{name(row)}{row.code?<small>{String(row.code)}</small>:null}</li>)}
    </ul>
    <nav className="fulfillment-pagination"><button type="button" disabled={page===1||read.busy} onMouseDown={e=>e.preventDefault()} onClick={()=>{setPage(p=>p-1);setActive(-1);}}>{t('previous')}</button><span>{page}</span><button type="button" disabled={read.busy||page*50>=(read.data?.total||0)} onMouseDown={e=>e.preventDefault()} onClick={()=>{setPage(p=>p+1);setActive(-1);}}>{t('next')}</button></nav></div>}
   </div></Field>
   <Field label={t('quantity')}><input required type="number" min="0.000001" step="any" value={quantity} onChange={e=>setQuantity(e.target.value)}/></Field>
   <Field label={t('unit')}><select required value={unit} onChange={e=>setUnit(e.target.value)}>{units.map(value=><option value={value} key={value}>{t(value)}</option>)}</select></Field>
   <Field label={t('warehousePurchaseDetails')}><textarea required={other} value={details} maxLength={4000} onChange={e=>setDetails(e.target.value)}/></Field>
   {!choice?.unit&&choice&&!other&&<p className="muted">{t('warehousePurchaseUnitHelp')}</p>}
   {other&&<p className="muted">{t('purchaseOtherHelp')}</p>}
   {read.busy&&<p role="status">{t('loading')}</p>}{(read.error||action.error)&&<p role="alert">{t(read.error||action.error)}</p>}
   <button className="primary" disabled={!choice||!quantity||Number(quantity)<=0||(other&&!details.trim())||read.busy||!props.can('warehouse','edit')}>{t('purchaseConfirm')}</button>
  </fieldset></form>
 </Dialog>;
}
