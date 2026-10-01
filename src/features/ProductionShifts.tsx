import { useState } from 'react';
import { Field, localName } from '@/components/ui';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
export default function ProductionShifts({snapshot:s,t,lang,can,command}:FeatureProps){
  const [editing,setEditing]=useState<Row|null>(null),[busy,setBusy]=useState(false),[error,setError]=useState('');
  const editable=can('settings','edit');
  async function save(name:string,name_ar:string,id:unknown=null,archived=false){
    setBusy(true);setError('');
    try{await command('configure_production_shift',{factory:s.factory?.id,name,name_ar,id,archived});setEditing(null);}
    catch(e){setError(e instanceof Error?e.message:'error');}finally{setBusy(false);}
  }
  return <section className="production-shifts"><h3>{t('productionShifts')}</h3><p className="muted">{t('shiftHelp')}</p>
    {(s.tables.production_shifts || []).map(x=><div className="row-actions" key={String(x.id)}><strong dir="auto">{localName(x,lang)}</strong>
      {x.archived && <small>{t('archived')}</small>}
      {editable && <><button disabled={busy} onClick={()=>setEditing(x)}>{t('edit')}</button>
      <button disabled={busy} onClick={()=>{if(x.archived || confirm(t('archive')+'?'))void save(String(x.name),String(x.name_ar),x.id,!x.archived);}}>{t(x.archived?'shiftReactivate':'archive')}</button></>}
    </div>)}
    {editable && <><button disabled={busy} onClick={()=>setEditing({})}>{t('shiftCreate')}</button>
    {editing && <form key={String(editing.id || 'new')} onSubmit={e=>{e.preventDefault();const data=new FormData(e.currentTarget);void save(String(data.get('name')),String(data.get('name_ar')),editing.id || null,Boolean(editing.archived));}}>
      <Field label={t('name')}><input name="name" required maxLength={120} defaultValue={String(editing.name||'')} disabled={busy}/></Field>
      <Field label={t('name_ar')}><input name="name_ar" dir="rtl" required maxLength={120} defaultValue={String(editing.name_ar||'')} disabled={busy}/></Field>
      <div className="row-actions"><button className="primary" disabled={busy}>{t('save')}</button><button type="button" disabled={busy} onClick={()=>setEditing(null)}>{t('cancel')}</button></div>
    </form>}</>}{error && <p role="alert">{t(error)}</p>}
  </section>;
}
