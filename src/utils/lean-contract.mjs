const uuid = v => typeof v === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
export const leanCommands = ['lean_command','record_lean_production','correct_lean_production'];
const fields = {
  cause: ['id','name','name_ar','parent_id'], standard: ['id','line_id','product_id','running_percent','startup_kg','expected_revision','proposal_month'],
  template: ['id','cause_id','title','name_ar','description','action_type','due_days','archived','expected_revision'],
  problem: ['mechanism','machine_id','line_id','product_id','cause_id','monitor_only','threshold_percent','expected_revision'],
  initiative: ['id','problem_id','product_id','title'], action: ['id','initiative_id','title','description','action_type','owner_id','due_date','expected_revision'],
  progress: ['id','status','due_date','note','expected_revision'],cancel_action: ['id','reason','expected_revision'],
  scrap_observation: ['id','entry_id','occurred_at','preliminary_cause_id','observation','response','downtime_id'],scrap_review: ['id','approved_cause_id','note','expected_revision'],
  record_lean_production: ['unit_kind','production_unit','item','technician','good','discarded_quantity','scrap_kg','startup_kg','notes','confirm_overproduction','shift','shift_override_reason','unfinished','remaining_work','input_lot','input_quantity','startup_id','startup_at'],
  correct_lean_production: ['entry','good','discarded_quantity','scrap_kg','startup_kg','reason','confirm_overproduction','shift','change_shift','unfinished','remaining_work']
};
export function leanCommandValid(command,args) {
  if (!leanCommands.includes(command) || !args || !uuid(args.factory) || !uuid(args.request_id) || !args.payload || typeof args.payload !== 'object' || Array.isArray(args.payload)) return false;
  if (Object.keys(args).some(k=>!['factory','request_id','payload',...(command==='lean_command'?['operation']:[])].includes(k))) return false;
  const allowed=fields[command==='lean_command'?args.operation:command];
  return Boolean(allowed && Object.keys(args.payload).every(k=>allowed.includes(k)) && Object.entries(args.payload).every(([k,v])=>
    !['scrap_kg','startup_kg','good','discarded_quantity','unfinished'].includes(k) || typeof v==='number' && Number.isFinite(v) && v>=0));
}
export function leanRequiredPermission(operation) {
  return operation==='standard'?['lean_standards','edit']:operation==='scrap_observation'?['orders','edit']:operation==='problem'?['factory','view']:operation==='initiative'?['lean','create']:operation==='progress'?['lean','view']:['lean','edit'];
}
