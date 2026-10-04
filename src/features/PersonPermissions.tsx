import { useState } from 'react';
import type { FeatureProps } from './types';
import { Field } from '@/components/ui';
import { packagePermissionPreview } from '@/utils/permission-packages.mjs';
import { usePermissionPackages, usePackageCommand, type PermissionPackagePage } from './usePermissionPackages';
import { PackageChoices, PermissionChoices, permissionCaption } from './PermissionPackageControls';
import PermissionPackages from './PermissionPackages';
export function MemberPermissions({ page, person, refresh, ...props }: FeatureProps & {page: PermissionPackagePage; person: string; refresh: () => void}) {
  const {snapshot:s,t,can} = props;
  const [selected,setSelected] = useState(page.package_ids), [direct,setDirect] = useState(page.direct);
  const [saved,setSaved] = useState(''), action = usePackageCommand(props.command);
  const preview = packagePermissionPreview(page.packages,selected,direct);
  const editable = can('roles','edit') && page.can_manage;
  const grantable = (keys: string[]) => keys.every(k => {const [m,a] = k.split(':');return can(m,a);});
  return <div>
    <p className="muted">{t('packageAssignmentHelp')}</p>
    <PackageChoices {...props} packages={page.packages} selected={selected} onChange={setSelected} disabled={!editable || action.busy} />
    <p aria-live="polite">{t('packageEffectiveCount')}: <strong>{preview.effective.length}</strong></p>
    <button className="primary" disabled={!editable || action.busy || !grantable(preview.inherited)} onClick={() => void action.run('set_member_permission_packages', {
      factory:s.factory?.id, person, packages:selected, expected_packages:page.package_ids,
    }, () => {setSaved('packageAssignmentSaved');refresh();})}>{t('packageSaveAssignment')}</button>
    {action.error && <p role="alert" className="toast">{t(action.error)}</p>}
    {saved && <p role="status">{t(saved)}</p>}
    <details className="permission-advanced"><summary>{t('packageAdvanced')}</summary>
      <h3>{t('packageIndividualAdditions')}</h3><p className="muted">{t('packageDirectHelp')}</p>
      <PermissionChoices {...props} definitions={s.tables.permissions || []} selected={direct} inherited={preview.inherited} onChange={setDirect} disabled={!editable || action.busy} />
      <button disabled={!editable || action.busy || !grantable(direct)} onClick={() => void action.run('set_member_direct_permissions', {
        factory:s.factory?.id,person,permissions:direct.map(key => {const [module,action] = key.split(':');return {module,action};}),expected_direct:page.direct,
      }, () => {setSaved('packageDirectSaved');refresh();})}>{t('packageSaveDirect')}</button>
      <h3>{t('packageEffectivePermissions')}</h3>
      <ul className="permission-effective">{preview.effective.map((key:string) => {const [m,a] = key.split(':');return <li key={key}>{permissionCaption(m,a,t)} <small>{t(preview.inherited.includes(key) ? direct.includes(key) ? 'packageBothSources' : 'packageInherited' : 'packageDirectSource')}</small></li>;})}</ul>
    </details>
  </div>;
}
function PersonDetail({person,...props}: FeatureProps & {person: string}) {
  const reader = usePermissionPackages(props.snapshot,person);
  return <>{reader.error && <p role="alert">{props.t(reader.error)}</p>}{reader.busy && <p role="status">{props.t('loading')}</p>}
    {reader.data && <MemberPermissions key={JSON.stringify([person,reader.data.package_ids,reader.data.direct,reader.data.packages.map(p => [p.id,p.revision])])}
      {...props} person={person} page={reader.data} refresh={reader.refresh} />}
    {reader.error && <button onClick={reader.refresh}>{props.t('refresh')}</button>}</>;
}
export default function PersonPermissions(props: FeatureProps) {
  const {snapshot:s,t} = props, [person,setPerson] = useState('');
  return <>
    <section className="panel"><h2>{t('packageMemberAccess')}</h2><p>{t('packageMemberHelp')}</p>
      <Field label={t('employee')}><select value={person} onChange={e => setPerson(e.target.value)}>
        <option value="">{t('chooseEmployee')}</option>{(s.tables.memberships || []).filter(m => !m.is_owner).map(m =>
          <option key={String(m.id)} value={String(m.user_id)}>{String(m.display_name)}</option>)}
      </select></Field>
      {person && <PersonDetail key={String(s.factory?.id)+':'+person} {...props} person={person} />}
    </section>
    <PermissionPackages {...props} />
  </>;
}
