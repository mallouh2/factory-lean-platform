const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
const object = value => !!value && typeof value === 'object' && !Array.isArray(value);
const ids = value => Array.isArray(value) && value.length <= 50 && value.every(uuid);
const keys = value => Array.isArray(value) && value.length <= 200 && value.every(x => typeof x === 'string' && /^[a-z_]+:[a-z_]+$/.test(x));
const grants = value => Array.isArray(value) && value.length <= 200 && value.every(x => object(x)
  && Object.keys(x).sort().join(',') === 'action,module' && /^[a-z_]+$/.test(x.module) && /^[a-z_]+$/.test(x.action));
export const packageCommands = ['save_permission_package', 'set_member_permission_packages', 'approve_member_packages', 'set_member_direct_permissions'];
export function packageCommandValid(command, args) {
  if (!object(args) || !uuid(args.factory)) return false;
  const fields = {
    save_permission_package: ['factory','package_id','payload','permissions','expected_revision'],
    set_member_permission_packages: ['factory','person','packages','expected_packages'],
    approve_member_packages: ['factory','id','role','packages','expected_packages'],
    set_member_direct_permissions: ['factory','person','permissions','expected_direct'],
  }[command];
  if (!fields || Object.keys(args).sort().join(',') !== fields.sort().join(',')) return false;
  if (command === 'save_permission_package') return uuid(args.package_id) && object(args.payload)
    && Object.keys(args.payload).every(k => ['name','name_ar','description'].includes(k))
    && typeof args.payload.name === 'string' && args.payload.name.trim().length > 0 && args.payload.name.length <= 120
    && ['name_ar','description'].every(k => args.payload[k] === undefined || typeof args.payload[k] === 'string' && args.payload[k].length <= (k === 'description' ? 1000 : 120))
    && grants(args.permissions) && Number.isSafeInteger(args.expected_revision) && args.expected_revision >= 0;
  if (command === 'set_member_direct_permissions') return uuid(args.person) && grants(args.permissions) && keys(args.expected_direct);
  return ids(args.packages) && ids(args.expected_packages) && (command === 'approve_member_packages' ? uuid(args.id) && uuid(args.role) : uuid(args.person));
}
// UI preview only: PostgreSQL remains the authorization authority.
export function packagePermissionPreview(packages, selected, direct = []) {
  const inherited = [...new Set(packages.filter(p => selected.includes(p.id)).flatMap(p => p.permissions))].sort();
  return { inherited, effective: [...new Set([...inherited, ...direct])].sort() };
}
