export const maintenanceStates = ['OPEN','ASSIGNED','IN_PROGRESS','COMPLETED','VERIFIED','CANCELLED'];
export const maintenancePriorities = ['LOW','NORMAL','HIGH','URGENT'];
export const maintenanceOperations = ['assign','priority','start','note','complete','verify','cancel'];
export const maintenanceFilterKeys = ['status','priority','machine','line','assignee','source','since','until','mine'];

export function maintenanceActions(request, userId, manager) {
  if (!request || ['VERIFIED','CANCELLED'].includes(request.status)) return [];
  const actions = [];
  if (manager) {
    if (['OPEN','ASSIGNED','IN_PROGRESS'].includes(request.status)) actions.push('assign');
    actions.push('priority','cancel');
    if (request.status === 'COMPLETED' && userId !== request.assigned_to && userId !== request.completed_by) actions.push('verify');
  }
  if (manager || userId === request.assigned_to) {
    if (request.status === 'ASSIGNED') actions.push('start');
    if (request.status === 'IN_PROGRESS') actions.push('note','complete');
  }
  return actions;
}

export function maintenanceCommandValid(command, args) {
  const create = command === 'create_maintenance_request';
  const keys = create ? ['factory','payload','request_id']
    : ['factory','maintenance_request','operation','payload','expected_revision','request_id'];
  if (!args || typeof args !== 'object' || Array.isArray(args) || Object.keys(args).some(key => !keys.includes(key))) return false;
  if (!args.payload || typeof args.payload !== 'object' || Array.isArray(args.payload)) return false;
  const payloadKeys = create ? ['work_center_id','downtime_id','title','description','priority','assigned_to','separate_problem']
    : { assign:['assigned_to'], priority:['priority'], start:[], note:['work_note'], complete:['work_note'],
      verify:['result','verification_note'], cancel:['cancellation_note'] }[args.operation];
  return Boolean(payloadKeys && Object.keys(args.payload).every(key => payloadKeys.includes(key))
    && (create || (Number.isSafeInteger(args.expected_revision) && args.expected_revision > 0)));
}
