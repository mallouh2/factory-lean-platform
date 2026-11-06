import type { MaintenanceRequest } from './maintenance-types';
export type MaintenanceSchedule = {
  id:string; maintenance_request_id:string; work_center_id:string; code:string; revision:number;
  state:'PROPOSED'|'CONFIRMED'|'INVALIDATED'|'UNSCHEDULED'|'RELEASED';
  planned_start:string; planned_end:string; hold_started_at:string|null; released_at:string|null;
  missed_window:boolean; actual_hold:boolean; overrun:boolean; invalid_reason:string|null;
  resources:{resource_kind:string; machine_id:string|null; line_id:string|null; impact_reason:string}[];
  line_ids?:string[];machine_ids?:string[];
  machine_code?:string;machine_name?:string;machine_name_ar?:string|null;
  occupancy?:{start:string;finish:string|null;continues:boolean;reserved:boolean};
  actual_stops?:{id:string;work_center_id:string;started_at:string;ended_at:string|null}[];
};
export type MaintenancePlanningBoard = {
  active:boolean; schedules:MaintenanceSchedule[]; requests:MaintenanceRequest[]; read_at:string;
  preview_available:boolean; history_available:boolean;
};
export type MaintenancePreview = {
  factory_id:string;evaluated_at:string;timezone:string;request_id:string;request_revision:number;schedule_revision:number;
  capacity:'CLEAR'|'BLOCKED'|'UNKNOWN'|'INCOMPLETE';eligible:boolean;binding:false;confirmation_available:boolean;activation_enabled?:boolean;
  context_hash:string;configuration_hash:string;duration_minutes:number|null;start:string;end:string|null;slack_minutes:number|null;
  scope:{kind:string;machine_id:string;line_id:string|null};physical_readiness:string;occupancy_complete:boolean;
  conditions:{configuration_or_routing_unknown:boolean;open_transfer:boolean;duration_unknown:boolean};
  conflicts:{code:string;reference_id:string;kind:string;state:string;start:string;end:string;unknown_end:boolean;unknown_window:boolean}[];
  conflicts_complete:boolean;
};
export type MaintenanceGaps = Omit<MaintenancePreview,'start'|'end'|'slack_minutes'|'conflicts'|'conflicts_complete'> & {suggestions:{start:string;end:string;gap_end:string}[];
  search_start:string;search_end:string;has_more:boolean;next_after_start:string|null;blocker_count:number;suggestions_complete:boolean;
  blockers:{code:string;reference_id:string;kind:string;state:string}[];blockers_complete:boolean};
export type MaintenanceRecordedScope = {kind:string;machine_id:string|null;line_id:string|null;impact_reason:string;machine_evidence:{line:string|null;dependency:string;scope:string;buffer:number}|null};
export type MaintenanceHistory = {request_id:string;schedule_id:string|null;through_revision:number;has_more:boolean;next_before_revision:number|null;
 rows:{revision:number;event:string;reason:string;actor_id:string|null;actor_name:string|null;changed_at:string;
  before_window:{start:string|null;end:string|null;state:string|null};after_window:{start:string;end:string;state:string};
  before_evidence:string;before_resources:MaintenanceRecordedScope[]|null;after_resources:MaintenanceRecordedScope[];released_at:string|null;before_hold:string|null;after_hold:string|null}[]};
