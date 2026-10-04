import { useState } from 'react';
import type { FeatureProps } from './types';
import type { Row } from '@/types';
import { Dialog, Field, localName } from '@/components/ui';
import { PackageChoices } from './PermissionPackageControls';
import { usePermissionPackages, usePackageCommand, type PermissionPackagePage } from './usePermissionPackages';
export function ApprovalForm({ member, page, onClose, ...props }: FeatureProps & {member:Row;page:PermissionPackagePage;onClose:()=>void}) {
  const {snapshot:s,t,lang,can} = props, [selected,setSelected] = useState(page.package_ids), [role,setRole] = useState(String(member.role_id || ''));
  const action = usePackageCommand(props.command);
  const allowed = can('employees','approve') && can('roles','edit') && page.can_manage;
  return <form onSubmit={e => {e.preventDefault();if (!allowed || !role) return;void action.run('approve_member_packages', {
    factory:s.factory?.id,id:member.id,role,packages:selected,expected_packages:page.package_ids,
  },onClose);}}><p>{t('packageApprovalHelp')}</p>
    <Field label={t('role')}><select required value={role} onChange={e => setRole(e.target.value)}><option value="">{t('role')}</option>
      {s.tables.roles?.map(r => <option key={String(r.id)} value={String(r.id)}>{localName(r,lang)}</option>)}</select></Field>
    <PackageChoices {...props} packages={page.packages} selected={selected} onChange={setSelected} disabled={action.busy || !allowed} />
    <p className="muted">{t('packageDirectPreserved')}</p>{action.error && <p role="alert">{t(action.error)}</p>}
    <button className="primary" disabled={action.busy || !allowed || !role}>{t('packageApprove')}</button>
  </form>;
}
export default function MemberPackageApproval({member,onClose,...props}: FeatureProps & {member:Row;onClose:()=>void}) {
  const reader = usePermissionPackages(props.snapshot,String(member.user_id));
  return <Dialog title={`${props.t('packageApprove')} · ${member.display_name}`} t={props.t} onClose={onClose}>
    {reader.busy && <p role="status">{props.t('loading')}</p>}{reader.error && <p role="alert">{props.t(reader.error)} <button onClick={reader.refresh}>{props.t('refresh')}</button></p>}
    {reader.data && <ApprovalForm key={JSON.stringify(reader.data.package_ids)} {...props} page={reader.data} member={member} onClose={onClose} />}
  </Dialog>;
}
