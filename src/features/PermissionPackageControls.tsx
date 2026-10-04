import type { FeatureProps } from './types';
import type { PermissionPackage } from './usePermissionPackages';
import type { Translate } from '@/types';
function permissionAction(module: string, action: string, t: Translate) {
  return module === 'maintenance' && action === 'edit' ? t('maintenanceManage')
    : module === 'orders' && action === 'create' ? t('createProductionRequest') : t(action);
}
export function permissionCaption(module: string, action: string, t: Translate) {
  return `${t(module)} · ${permissionAction(module,action,t)}`;
}
export function PackageChoices({ packages, selected, onChange, disabled, can, t, lang }: Pick<FeatureProps, 'can'|'t'|'lang'> & {
  packages: PermissionPackage[]; selected: string[]; onChange: (value: string[]) => void; disabled: boolean;
}) {
  return <fieldset className="permission-package-choices" disabled={disabled}><legend>{t('permissionPackages')}</legend>
    {packages.map(p => <label className="check" key={p.id}><input type="checkbox" checked={selected.includes(p.id)}
      disabled={!selected.includes(p.id) && !p.permissions.every(key => { const [m,a] = key.split(':'); return can(m,a); })}
      onChange={e => onChange(e.target.checked ? [...selected, p.id] : selected.filter(id => id !== p.id))} />
      <span>{lang === 'ar' && p.name_ar ? p.name_ar : p.name}<small>{p.permissions.length} {t('packagePermissionCount')}</small></span>
    </label>)}
  </fieldset>;
}
export function PermissionChoices({ definitions, selected, inherited = [], onChange, disabled, can, t }: Pick<FeatureProps,'can'|'t'> & {
  definitions: Record<string, unknown>[]; selected: string[]; inherited?: string[]; onChange: (keys: string[]) => void; disabled: boolean;
}) {
  const modules = [...new Set(definitions.map(p => String(p.module)))];
  return <div className="permission-details">{modules.map(module => <fieldset key={module} disabled={disabled}><legend>{t(module)}</legend>
    {definitions.filter(p => p.module === module).map(p => { const action = String(p.action), key = `${module}:${action}`;
      return <label className="check" key={key}><input type="checkbox" aria-label={permissionCaption(module,action,t)} checked={selected.includes(key)} disabled={!can(module,action)}
        onChange={e => onChange(e.target.checked ? [...selected,key] : selected.filter(k => k !== key))} />
        <span>{permissionAction(module,action,t)}{inherited.includes(key) && <small>{t('packageInherited')}</small>}</span></label>;
    })}</fieldset>)}</div>;
}
