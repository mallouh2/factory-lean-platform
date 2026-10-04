import { useEffect, useRef, useState } from 'react';
import { Dialog, Field } from '@/components/ui';
import type { FeatureProps } from './types';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';

export type SupplierChoice = { id: string; name: string };
export default function PurchaseSupplier(props: FeatureProps & { value: SupplierChoice; onChange: (value: SupplierChoice) => void; onSave: (value?: SupplierChoice) => void; busy: boolean }) {
 const {snapshot:s,t,value,onChange}=props;
 const [open,setOpen]=useState(false),[page,setPage]=useState(1),[active,setActive]=useState(-1),[adding,setAdding]=useState(false);
 const input=useRef<HTMLInputElement>(null);
 const root=useRef<HTMLDivElement>(null);
 useEffect(()=>{if(!open)return;const close=(e:PointerEvent)=>{if(!root.current?.contains(e.target as Node)){setOpen(false);setActive(-1);}};document.addEventListener('pointerdown',close);return()=>document.removeEventListener('pointerdown',close);},[open]);
 const read=useSupply(s,'suppliers',{page:String(page),filters:JSON.stringify({search:value.id?'':value.name.trim()})});
 const action=useSupplyCommand(props.command,s.factory?.id);
 const rows=(read.data?.rows||[]).filter(row=>row.active);
 const exact=(read.data?.rows||[]).find(row=>String(row.name).trim().toLowerCase()===value.name.trim().toLowerCase());
 function choose(row:SupplyRow){onChange({id:String(row.id),name:String(row.name)});setOpen(false);setActive(-1);}
 return <div className="purchase-supplier" ref={root}>
  <Field label={t('supplier')}><div className="orders-v2-product-combobox warehouse-purchase-item">
   <input ref={input} role="combobox" aria-label={t('supplier')} autoComplete="off" maxLength={200} value={value.name} placeholder={t('purchaseSupplierPlaceholder')} disabled={props.busy||action.busy}
    aria-autocomplete="list" aria-expanded={open} aria-controls="purchase-supplier-options" aria-activedescendant={open&&active>=0&&rows[active]?'purchase-supplier-'+String(rows[active].id):undefined}
    onFocus={()=>{setOpen(true);setPage(1);setActive(-1);}} onBlur={e=>{if(!e.relatedTarget||root.current?.contains(e.relatedTarget))return;setOpen(false);setActive(-1);}}
    onChange={e=>{onChange({id:'',name:e.target.value});setPage(1);setOpen(true);setActive(-1);}}
    onKeyDown={e=>{if(e.key==='ArrowDown'||e.key==='ArrowUp'){e.preventDefault();setOpen(true);if(rows.length)setActive(e.key==='ArrowDown'?(active+1)%rows.length:(active+rows.length-1)%rows.length);}
     else if(e.key==='Enter'&&open){e.preventDefault();if(active>=0&&rows[active])choose(rows[active]);else setOpen(false);}
     else if(e.key==='Escape'){e.preventDefault();setOpen(false);}
     else if(e.key==='PageDown'&&open&&page*50<(read.data?.total||0)){e.preventDefault();setPage(p=>p+1);setActive(-1);}
     else if(e.key==='PageUp'&&open&&page>1){e.preventDefault();setPage(p=>p-1);setActive(-1);}}}/>
   <span className="orders-v2-product-caret" aria-hidden="true">⌄</span>
   {open&&<div className="warehouse-purchase-options"><ul id="purchase-supplier-options" role="listbox" aria-label={t('supplier')} className="orders-v2-product-options">
    {rows.map((row,index)=><li key={String(row.id)} id={'purchase-supplier-'+String(row.id)} role="option" aria-selected={value.id===row.id} className={active===index?'is-active':''} onPointerDown={e=>e.preventDefault()} onClick={()=>choose(row)}>{String(row.name)}</li>)}
    {!rows.length&&!read.busy&&<li role="presentation">{t('purchaseSupplierLocalHelp')}</li>}
   </ul><nav className="fulfillment-pagination"><button type="button" disabled={page===1||read.busy} onPointerDown={e=>e.preventDefault()} onClick={()=>{setPage(p=>p-1);setActive(-1);}}>{t('previous')}</button><span>{page}</span><button type="button" disabled={page*50>=(read.data?.total||0)||read.busy} onPointerDown={e=>e.preventDefault()} onClick={()=>{setPage(p=>p+1);setActive(-1);}}>{t('next')}</button></nav></div>}
  </div></Field>
  {read.busy&&<p role="status">{t('loading')}</p>}{read.error&&<p role="alert">{t(read.error)}</p>}
  <div className="row-actions"><button type="button" disabled={props.busy||action.busy||!value.name.trim()||read.busy||!!read.error||exact?.active===false} onMouseDown={e=>e.preventDefault()} onClick={()=>{setOpen(false);props.onSave(value);}}>{t('purchaseSaveSupplier')}</button>
   {!value.id&&!exact&&value.name.trim()&&!read.busy&&!read.error&&props.can('suppliers','edit')&&<button type="button" disabled={props.busy||action.busy} onMouseDown={e=>e.preventDefault()} onClick={()=>{setOpen(false);setAdding(true);action.clearError();}}>{t('purchaseAddSupplier')}</button>}
  </div>
  {!value.id&&value.name.trim()&&!exact&&<p className="muted">{t('purchaseSupplierLocalHelp')}</p>}
  {exact?.active===false&&<p role="alert">{t('purchaseSupplierInactive')}</p>}
  {adding&&<Dialog title={t('purchaseAddSupplier')} t={t} onClose={()=>{if(!action.busy){setAdding(false);queueMicrotask(()=>input.current?.focus());}}}>
   <form onSubmit={async e=>{e.preventDefault();if(!props.can('suppliers','edit'))return;const data=new FormData(e.currentTarget);
    if(await action.run('supplier_save',{name:String(data.get('name')).trim(),phone:String(data.get('phone')||''),email:String(data.get('email')||''),notes:String(data.get('notes')||''),active:true},result=>{const choice={id:String(result),name:String(data.get('name')).trim()};onChange(choice);props.onSave(choice);})){setAdding(false);read.refresh();queueMicrotask(()=>input.current?.focus());}
   }}><fieldset className="fulfillment-form" disabled={action.busy}>
    <Field label={t('supplierField_name')}><input name="name" required maxLength={200} defaultValue={value.name.trim()}/></Field>
    <Field label={t('supplierField_phone')}><input name="phone" maxLength={100}/></Field>
    <Field label={t('supplierField_email')}><input name="email" type="email" maxLength={200}/></Field>
    <Field label={t('notes')}><textarea name="notes" maxLength={4000}/></Field>
    {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('save')}</button>
   </fieldset></form>
  </Dialog>}
 </div>;
}
