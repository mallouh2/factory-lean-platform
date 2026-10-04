import { useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field } from '@/components/ui';
import { useSupply, useSupplyCommand, type SupplyRow } from './useSupply';
export default function Suppliers(props: FeatureProps) {
  const { snapshot:s, t, lang, can } = props;
  const [page,setPage]=useState(1),[editing,setEditing]=useState<SupplyRow|null>(null),[relationship,setRelationship]=useState('ALTERNATIVE');
  const read=useSupply(s,'suppliers',{page:String(page)}),action=useSupplyCommand(props.command,s.factory?.id);
  return <section className="panel supply-page" dir={lang==='ar'?'rtl':'ltr'}>
    <header className="section-head"><h2>{t('supplierDirectory')}</h2>{can('suppliers','edit')&&<button className="primary" onClick={()=>{setEditing({});setRelationship('ALTERNATIVE');action.clearError();}}>{t('supplierCreate')}</button>}</header>
    {read.error&&<p role="alert">{t(read.error)}</p>}{read.busy&&<p role="status">{t('loading')}</p>}
    {!read.busy&&!read.data?.rows.length&&<p className="empty">{t('supplierEmpty')}</p>}
    <div className="supply-directory">{read.data?.rows.map(row=><article key={String(row.id)}>
      <strong>{String(row.name)}</strong><p>{String(row.primary_contact)}</p><p><bdi>{String(row.phone)}</bdi> · <bdi>{String(row.email)}</bdi></p>
      <p>{t(row.active?'supplierActive':'supplierInactive')}</p>{((row.categories||[]) as SupplyRow[]).map(link=><p key={String(link.name)}>{String(link.name)} · {t('supplier_'+String(link.relationship))}</p>)}
      {Boolean(row.notes)&&<details><summary>{t('notes')}</summary><p className="supply-note">{String(row.notes)}</p></details>}
      {can('suppliers','edit')&&<button onClick={()=>{setEditing(row);setRelationship('ALTERNATIVE');action.clearError();}}>{t('edit')}</button>}
    </article>)}</div>
    <nav className="fulfillment-pagination"><button disabled={page===1||read.busy} onClick={()=>setPage(x=>x-1)}>{t('previous')}</button><span>{page}</span><button disabled={read.busy||page*50>=(read.data?.total||0)} onClick={()=>setPage(x=>x+1)}>{t('next')}</button></nav>
    {editing&&<Dialog title={t(editing.id?'edit':'supplierCreate')} t={t} onClose={()=>{if(!action.busy)setEditing(null);}}>
      <form onSubmit={async e=>{e.preventDefault();const data=new FormData(e.currentTarget);if(await action.run('supplier_save',{...Object.fromEntries(data),...(editing.id?{id:editing.id}:{}),active:data.get('active')==='on',replace_primary:data.get('replace_primary')==='on'})){setEditing(null);read.refresh();}}}>
        <fieldset disabled={action.busy} className="form-grid">
          {['name','primary_contact','phone','email','notes','category'].map(key=><Field key={key} label={t('supplierField_'+key)}>{key==='notes'?<textarea name={key} maxLength={4000} defaultValue={String(editing[key]||'')}/>:<input name={key} required={key==='name'} type={key==='email'?'email':'text'} maxLength={key==='phone'?100:key==='category'?120:200} defaultValue={String(editing[key]||'')}/>}</Field>)}
          <Field label={t('supplierRelationship')}><select name="relationship" value={relationship} onChange={e=>setRelationship(e.target.value)}>{['PRIMARY','ALTERNATIVE'].map(value=><option key={value} value={value}>{t('supplier_'+value)}</option>)}</select></Field>
          {relationship==='PRIMARY'&&<label><input type="checkbox" name="replace_primary"/>{t('supplierReplacePrimary')}</label>}
          <label><input type="checkbox" name="active" defaultChecked={editing.active!==false}/>{t('supplierActive')}</label>
          {action.error&&<p role="alert">{t(action.error)}</p>}<button className="primary">{t('save')}</button>
        </fieldset></form></Dialog>}
  </section>;
}
