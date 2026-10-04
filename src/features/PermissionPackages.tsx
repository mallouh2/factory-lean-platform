import { useState } from 'react';
import type { FeatureProps } from './types';
import { Dialog, Field } from '@/components/ui';
import { PermissionChoices, permissionCaption } from './PermissionPackageControls';
import { usePermissionPackages, usePackageCommand, type PermissionPackage } from './usePermissionPackages';
export function PackageEditor({ item, onClose, ...props }: FeatureProps & {item: PermissionPackage; onClose: () => void}) {
  const {snapshot:s,t,can} = props, action = usePackageCommand(props.command);
  const [selected,setSelected] = useState(item.permissions), [name,setName] = useState(item.name), [ar,setAr] = useState(item.name_ar), [note,setNote] = useState(item.description);
  const [confirmed,setConfirmed] = useState(false);
  const allowed = can('roles','edit') && selected.every(k => {const [m,a] = k.split(':');return can(m,a);});
  return <Dialog title={t(item.revision ? 'packageEdit' : 'packageCreate')} t={t} onClose={onClose}>
    <form onSubmit={e => {e.preventDefault();if (!allowed || !name.trim() || item.assigned_count > 0 && !confirmed) return;
      void action.run('save_permission_package',{factory:s.factory?.id,package_id:item.id,payload:{name:name.trim(),name_ar:ar.trim(),description:note.trim()},
        permissions:selected.map(key => {const [module,action] = key.split(':');return {module,action};}),expected_revision:item.revision},onClose);
    }}>
      <div className="form-grid"><Field label={t('packageNameEn')}><input value={name} required maxLength={120} onChange={e => setName(e.target.value)} /></Field>
        <Field label={t('packageNameAr')}><input value={ar} dir="rtl" maxLength={120} onChange={e => setAr(e.target.value)} /></Field></div>
      <Field label={t('description')}><textarea value={note} maxLength={1000} onChange={e => setNote(e.target.value)} /></Field>
      <PermissionChoices {...props} definitions={s.tables.permissions || []} selected={selected} onChange={setSelected} disabled={action.busy || !can('roles','edit')} />
      {item.assigned_count > 0 && <label className="check"><input type="checkbox" checked={confirmed} onChange={e => setConfirmed(e.target.checked)} />
        <span>{t('packageEditImpact')} ({item.assigned_count})</span></label>}
      {action.error && <p className="toast" role="alert">{t(action.error)}</p>}
      <button className="primary" disabled={action.busy || !allowed || !name.trim() || item.assigned_count > 0 && !confirmed}>{t('save')}</button>
    </form>
  </Dialog>;
}
export default function PermissionPackages(props: FeatureProps) {
  const {t,lang,can,snapshot:s} = props, reader = usePermissionPackages(s), [editing,setEditing] = useState<PermissionPackage|null>(null);
  return <section className="panel"><header className="section-head"><h2>{t('permissionPackages')}</h2>
    {can('roles','edit') && <button onClick={() => setEditing({id:crypto.randomUUID(),name:'',name_ar:'',description:'',permissions:[],revision:0,assigned_count:0})}>{t('packageCreate')}</button>}</header>
    <p className="muted">{t('packageManagementHelp')}</p>
    {reader.error && <p role="alert">{t(reader.error)} <button onClick={reader.refresh}>{t('refresh')}</button></p>}
    {reader.busy && <p role="status">{t('loading')}</p>}
    <div className="permission-package-list">{reader.data?.packages.map(p => <details key={p.id}>
      <summary><strong>{lang === 'ar' && p.name_ar ? p.name_ar : p.name}</strong> <span>{p.permissions.length} {t('packagePermissionCount')} · {p.assigned_count} {t('packagePeopleCount')}</span></summary>
      {p.description && <p>{p.description}</p>}
      <ul className="permission-effective">{p.permissions.map(key => {const [m,a] = key.split(':');return <li key={key}>{permissionCaption(m,a,t)}</li>;})}</ul>
      {can('roles','edit') && <button onClick={() => setEditing(p)}>{t('packageEdit')}</button>}
    </details>)}</div>
    {editing && <PackageEditor key={editing.id} {...props} item={editing} onClose={() => {setEditing(null);reader.refresh();}} />}
  </section>;
}
