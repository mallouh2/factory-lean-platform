// Testing-only presentation masks. They never leave the browser or change grants.
export const previewPresets = {
  full: null,
  sales: ["factory:view", "orders:view", "orders:create"],
  planning: ["factory:view", "dashboard:view", "orders:view", "orders:edit", "lines:view", "centers:view"],
  production: ["factory:view", "dashboard:view", "lines:view", "centers:view", "orders:view", "orders:edit", "centers:edit", "machine_status:edit", "downtime:view", "downtime:create", "downtime:edit"],
  technician: ["factory:view", "lines:view", "centers:view", "machine_status:edit", "downtime:view", "downtime:create"],
  hr: ["factory:view", "employees:view", "employees:create", "employees:edit", "employees:approve"],
};

export function previewPermissions(realPermissions, preset) {
  if (preset === "full") return realPermissions;
  const allowed = previewPresets[preset];
  return allowed ? realPermissions.filter((permission) => allowed.includes(permission)) : [];
}

export function hasEveryDefinedPermission(realPermissions, definitions) {
  if (!Array.isArray(realPermissions) || !Array.isArray(definitions) || !definitions.length) return false;
  const granted = new Set(realPermissions);
  return definitions.every(({ module, action }) => granted.has(`${module}:${action}`));
}
