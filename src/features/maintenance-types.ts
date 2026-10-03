import type { Row } from '@/types';
export type MaintenanceRequest = {
  id: string; factory_id: string; code: string; work_center_id: string; line_id: string | null; downtime_id: string | null;
  title: string; description: string; priority: string; source: string; status: string; revision: number;
  requested_by: string; requested_by_name: string; requested_at: string; assigned_to: string | null;
  assigned_at: string | null; started_at: string | null; completed_at: string | null; completed_by: string | null;
  verified_at: string | null; verified_by: string | null; checked_at: string | null; cancelled_at: string | null;
  verification_result: string | null; work_note: string; verification_note: string; cancellation_note: string;
  machine_name: string; machine_name_ar: string | null; machine_code: string; line_name: string | null; line_name_ar: string | null;
  assignee_name: string | null; completer_name: string | null; verifier_name: string | null; checker_name: string | null;
  downtime: Row | null; saved_loss: Record<string, unknown> | null;
};
export type MaintenancePage = {
  rows: MaintenanceRequest[]; total: number; counts: Record<string, number>; detail: MaintenanceRequest | null;
  wide: boolean; options: { machines: Row[]; lines: Row[]; people: Row[] };
  history: { id: string; actor_name: string | null; action: string; created_at: string;
    old_data: MaintenanceRequest | null; new_data: MaintenanceRequest | null }[]; history_total: number;
};
