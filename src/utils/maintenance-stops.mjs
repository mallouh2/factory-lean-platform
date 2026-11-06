const uuid = value => typeof value === 'string' && /^[\da-f]{8}-[\da-f]{4}-[\da-f]{4}-[\da-f]{4}-[\da-f]{12}$/i.test(value);
const revision = value => Number.isSafeInteger(value) && value >= 0;
export const maintenanceStopCommands = ['stop_machine_for_maintenance', 'correct_maintenance_stop'];
export function maintenanceStopCommandValid(command, args) {
  if (!args || !uuid(args.factory) || !uuid(args.request_id) || !revision(args.expected_revision) || !uuid(args.schedule)) return false;
  const keys = command === 'stop_machine_for_maintenance'
    ? ['factory','work_center','nature','reason','activity','notes','schedule','expected_revision','expected_request_revision','request_id']
    : ['factory','event','schedule','approval_revision','operation','reason','expected_revision','request_id'];
  if (Object.keys(args).some(key => !keys.includes(key))) return false;
  if (command === 'stop_machine_for_maintenance') return uuid(args.work_center) && revision(args.expected_request_revision)
    && typeof args.notes === 'string' && args.notes.length <= 2000 && (args.nature === 'unplanned'
      ? uuid(args.reason) && args.activity === null : args.nature === 'planned' && args.reason === null
        && ['cleaning','changeover','preventive_maintenance','inspection','planned_process','other'].includes(args.activity));
  return command === 'correct_maintenance_stop' && uuid(args.event) && revision(args.approval_revision)
    && ['LINK','UNLINK'].includes(args.operation) && typeof args.reason === 'string' && args.reason.trim().length > 0 && args.reason.length <= 4000;
}
