const operations = {
  save: ['start','reason','context_hash','request_revision'],
  details: ['maintenance_kind','estimated_duration_minutes','preferred_start','preferred_end','planning_notes',
    'work_center_id','title','description','priority'],
  propose: ['start','end','reason'], confirm: ['reason','context_hash','request_revision'], reschedule: ['start','end','reason','context_hash','request_revision'], unschedule: ['reason'],
};
const requiresProof = operation => ['confirm','reschedule','save'].includes(operation);
export function maintenanceKindCanBook(request) {
  return request.maintenance_kind==='PLANNED' ||
    (request.maintenance_kind==='CORRECTIVE' && request.source==='MANUAL' && !request.downtime_id);
}
export function maintenancePlanningPermissions(operation) {
  return operation === 'details' ? [['maintenance','edit']] : [['maintenance','view'],['orders','edit'],...(requiresProof(operation) ? [['orders','view']] : [])];
}
export function maintenancePlanningCommandValid(args) {
  if (!args || typeof args !== 'object' || Array.isArray(args) ||
    Object.keys(args).some(k => !['factory','maintenance_request','operation','payload','expected_revision','request_id'].includes(k))) return false;
  const keys = operations[args.operation];
  if (requiresProof(args.operation) && (!/^[a-f0-9]{64}$/.test(args.payload?.context_hash || '') ||
    !Number.isSafeInteger(args.payload?.request_revision) || args.payload.request_revision < 1)) return false;
  if (args.operation==='save' && (typeof args.payload?.start!=='string' || !Number.isFinite(Date.parse(args.payload.start)))) return false;
  return Boolean(keys && args.payload && typeof args.payload === 'object' && !Array.isArray(args.payload) &&
    Object.keys(args.payload).every(k => keys.includes(k)) && Number.isSafeInteger(args.expected_revision) && args.expected_revision >= 0);
}

/** The preview remains advisory; the command repeats all validation under database locks. */
export function maintenancePreviewCurrent(preview, {factory,request,requestRevision,scheduleRevision,start,end,timezone,now=Date.now(),requireActivation=false}) {
  return Boolean(preview && (!requireActivation || preview.activation_enabled===true && preview.confirmation_available===true) && preview.request_id===request && preview.request_revision===requestRevision &&
    preview.schedule_revision===scheduleRevision && preview.timezone===timezone && preview.scope?.machine_id &&
    preview.capacity==='CLEAR' && preview.eligible && preview.occupancy_complete && /^[a-f0-9]{64}$/.test(preview.context_hash) &&
    preview.factory_id===factory && Number.isFinite(Date.parse(start)) && Date.parse(preview.start)===Date.parse(start) &&
    Number.isFinite(Date.parse(preview.end)) && (!end || Date.parse(preview.end)===Date.parse(end)) &&
    now>=Date.parse(preview.evaluated_at) && now-Date.parse(preview.evaluated_at)<=60000);
}
