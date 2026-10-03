import { NextRequest, NextResponse } from "next/server";
import {
  authenticatedClient,
  authorize,
  verifyOrigin,
  safeError,
} from "@/services/authorization";
import { hasEveryDefinedPermission } from "@/utils/permission-preview.mjs";
import { maintenanceCommandValid } from '@/utils/maintenance.mjs';
export async function GET(req: NextRequest) {
  let stage = "authentication";
  try {
    const { db, user } = await authenticatedClient();
    if(req.nextUrl.searchParams.get('shift_context')==='1'){
      stage='production_shift_context';
      const {data: context,error: contextError}=await db.rpc('production_shift_context',{factory:req.nextUrl.searchParams.get('factory')});
      if(contextError)throw contextError;
      return NextResponse.json(context);
    }
    stage = "factory_snapshot";
    const { data, error } = await db.rpc("factory_snapshot", {
      factory: req.nextUrl.searchParams.get("factory") || null,
    });
    if (error) throw error;
    if (data?.factory?.id && data.permissions?.includes("orders:view")) {
      stage = "production_recording_units";
      const { data: recording, error: recordingError } = await db.rpc("production_recording_units", { factory: data.factory.id });
      if (recordingError) throw recordingError;
      data.tables.production_recording_units = recording.units;
      data.tables.production_technicians = recording.technicians;
    }
    if (data?.factory?.id && (data.permissions?.includes('orders:view') || data.permissions?.includes('settings:view'))) {
      stage = "production_shifts";
      const {data: shifts,error: shiftError}=await db.from('production_shifts').select('*').eq('factory_id',data.factory.id).order('created_at');
      if(shiftError) throw shiftError;
      data.tables.production_shifts=shifts;
      stage = 'production_shift_context';
      const {data: context,error: contextError}=await db.rpc('production_shift_context',{factory:data.factory.id});
      if(contextError)throw contextError;
      data.tables.production_shift_context=[context];
    }
    return NextResponse.json({
      ...data,
      user: { id: user.id, email: user.email },
      testingPreviewEligible:
        process.env.APP_ENV === "development" &&
        process.env.VERCEL_ENV !== "production" &&
        process.env.SUPABASE_URL === "https://silmfbpjyepalnggwulp.supabase.co" &&
        data?.membership?.status === "approved" &&
        hasEveryDefinedPermission(data?.permissions, data?.tables?.permissions),
    });
  } catch (e) {
    // Server diagnostics only; never send database details or credentials to the UI.
    console.warn("factory_snapshot_failed", { stage,
      code: e && typeof e === "object" && "code" in e ? e.code : undefined,
      reason: e && typeof e === "object" && "message" in e ? e.message : "unknown" });
    const code = e && typeof e === "object" && "code" in e ? e.code : null;
    if (e instanceof Error && e.message === "unauthorized")
      return NextResponse.json(safeError(e), { status: 401 });
    if (code === "42501" || (e && typeof e==='object' && 'message' in e && e.message === "permission_denied"))
      return NextResponse.json({ error: "permissionError" }, { status: 403 });
    // Loading failures are not permission denials. Keep the existing localized
    // data warning and internal database details on the server.
    return NextResponse.json({ error: "dataWarning" }, { status: 503 });
  }
}
const commandErrors: Record<string, string> = {
  maintenance_invalid: 'maintenanceInvalid',
  maintenance_machine: 'maintenanceInvalidMachine',
  maintenance_downtime: 'maintenanceInvalidDowntime',
  maintenance_assignee: 'maintenanceInvalidAssignee',
  maintenance_state: 'maintenanceInvalidState',
  maintenance_conflict: 'maintenanceConflict',
  maintenance_note: 'maintenanceNoteRequired',
  maintenance_missing: 'noResults',
  maintenance_existing: 'maintenanceExistingProblem',
  maintenance_independent_verifier: 'maintenanceIndependentVerifier',
  internal_reason_required: 'internalReasonRequired',
  fulfillment_invalid: 'fulfillmentInvalid',
  fulfillment_product: 'fulfillmentProduct',
  fulfillment_state: 'fulfillmentState',
  fulfillment_hold: 'fulfillmentHold',
  fulfillment_not_ready: 'fulfillmentNotReady',
  fulfillment_stock_committed: 'fulfillmentStockCommitted',
  fulfillment_planner_decision: 'fulfillmentPlannerDecision',
  shift_invalid: 'shiftInvalid',
  shift_required: 'shiftRequired',
  shift_window_invalid: 'shiftWindowInvalid',
  shift_overlap: 'shiftOverlap',
  shift_no_match: 'shiftNoMatch',
  shift_override_reason: 'shiftOverrideReasonRequired',
  recording_invalid_quantity: "recordingInvalidQuantity",
  recording_invalid_unit: "recordingInvalidUnit",
  recording_overproduction_confirmation: "recordingOverproductionConfirm",
  recording_correction_reason: "recordingCorrectionReason",
  invalid_operator: "recordingInvalidTechnician",
  request_conflict: "recordingRequestConflict",
  layout_conflict: "layoutConflict",
  use_transfer_command: "useTransferCommand",
  description_required: "reasonDescriptionRequired",
  invalid_restart_time: "restartTimeInvalid",
  invalid_order: "activeOrderRequired",
  invalid_alternative: "alternativeInvalid",
  support_account_not_found: "supportNotFound",
  cannot_grant_higher_permissions: "permissionError",
  owner_required: "permissionError",
  invalid_category: "invalidCategory",
  category_in_use: "categoryInUse",
  category_alternative_conflict: "categoryAlternativeConflict",
  incompatible_alternative: "incompatibleAlternative",
  unfinished_invalid: "unfinishedInvalid",
  unfinished_invalid_lot: "unfinishedInvalidLot",
  unfinished_insufficient: "unfinishedInsufficient",
  unfinished_conservation: "unfinishedConservation",
  unfinished_already_consumed: "unfinishedAlreadyConsumed",
  history_unit_required: "historyUnitRequired",
  planning_already_started: "planningAlreadyStarted",
  planning_invalid_start: "planningInvalidStart",
  planning_incompatible_line: "planningIncompatibleLine",
  planning_missing_rate: "planningMissingRate",
  planning_ambiguous_rate: "planningAmbiguousRate",
  planning_ambiguous_setup: "planningAmbiguousSetup",
  planning_invalid_calendar: "planningInvalidCalendar",
  planning_invalid_quantity: "planningInvalidQuantity",
  planning_unknown_block: "planningUnknownBlock",
  planning_overlap: "planningOverlap",
  planning_locked: "planningLockedMessage",
  planning_reason_required: "planningReasonRequired",
  execution_use_command: "executionUseCommand",
  execution_already_started: "executionAlreadyStarted",
  execution_plan_required: "executionPlanRequired",
  execution_line_busy: "executionLineBusy",
  execution_out_of_sequence: "executionOutOfSequence",
  execution_not_running: "executionNotRunning",
  downtime_invalid_interval: "downtimeInvalidInterval",
  downtime_overlap: "downtimeOverlap",
  downtime_initial_locked: "downtimeInitialLocked",
  downtime_approval_locked: "downtimeApprovalLocked",
  downtime_not_reviewable: "downtimeNotReviewable",
  downtime_immutable: "downtimeImmutable",
  reason_required: "reasonRequired",
  invalid_planned_activity: "lossInvalidPlannedActivity",
  invalid_stop_nature: "lossInvalidStopType",
  loss_profile_incompatible: "lossProfileIncompatible",
  loss_recovery_incompatible: "lossRecoveryIncompatible",
  loss_estimate_incomplete: "lossMissing",
  loss_estimate_context_mismatch: "lossEstimateContextMismatch",
  loss_estimate_locked: "lossEstimateLocked",
  loss_actual_nonnegative: "lossActualNonnegative",
  loss_scrap_need_total_or_both: "lossScrapNeedTotalOrBoth",
  loss_scrap_breakdown_exceeds_total: "lossScrapBreakdownExceedsTotal",
  loss_scrap_breakdown_mismatch: "lossScrapBreakdownMismatch",
  loss_actual_invalid_unit: "lossActualInvalidUnit",
  loss_actual_at_least_one: "lossActualAtLeastOne",
};
/** request_membership reports failures as JSONB values instead of raising; map them to specific client keys. */
const joinErrors: Record<string, string> = {
  invalid_join_code: "invalidJoinCode",
  rate_limited: "rateLimited",
  already_joined: "alreadyJoined",
};
/** Pre-checks mirror the require_permission calls inside each RPC; the database remains authoritative. */
const rpcModules: Record<string, [string, string][]> = {
  create_maintenance_request: [['factory','view'],['maintenance','create']],
  create_sales_order: [['sales_orders', 'create']],
  approve_sales_order: [['sales_orders', 'approve']],
  change_sales_order: [['sales_orders', 'edit']],
  dispatch_sales_order: [['warehouse', 'issue']],
  configure_product_stock: [['warehouse', 'edit']],
  adjust_finished_stock: [['warehouse', 'edit']],
  configure_delivery_buffer: [['settings', 'edit']],
  configure_production_shift: [['settings','edit']],
  create_production_request: [["orders", "create"]],
  plan_product_item: [["orders", "edit"]],
  revise_product_plan: [["orders", "edit"]],
  set_plan_lock: [["orders", "edit"]],
  start_product_item: [["orders", "edit"]],
  finish_product_item: [["orders", "edit"]],
  approve_downtime_cause: [["downtime", "edit"]],
  approve_planned_downtime: [["downtime", "edit"]],
  correct_downtime_classification: [["downtime", "edit"]],
  record_production_loss_actuals: [["downtime", "edit"]],
  save_production_loss_estimate: [["downtime", "edit"]],
  configure_production_loss_profile: [["centers", "edit"], ["downtime", "edit"]],
  configure_production_loss_recovery_rate: [["centers", "edit"], ["downtime", "edit"]],
  record_missed_downtime: [["downtime", "edit"]],
  set_user_permissions: [["roles", "edit"]],
  save_line_layout: [
    ["lines", "edit"],
    ["centers", "edit"],
  ],
  transfer_production: [
    ["centers", "edit"],
    ["orders", "edit"],
  ],
  configure_center_alternatives: [["centers", "edit"]],
  configure_center_capabilities: [["centers", "edit"]],
  set_line_pause: [["centers", "edit"]],
  set_support_by_email: [["support", "edit"]],
  set_daily_target: [["orders", "edit"]],
  record_output: [["orders", "edit"]],
  record_production: [["orders", "edit"], ["orders", "view"]],
  correct_production_entry: [["orders", "edit"], ["orders", "view"]],
  record_access: [["reports", "export"]],
  manage_member: [["employees", "approve"]],
  get_join_code: [["settings", "edit"]],
  update_settings: [["settings", "edit"]],
  configure_working_calendar: [["settings", "edit"]],
  set_permissions: [["roles", "edit"]],
  set_support: [["support", "edit"]],
};
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    if (Number(req.headers.get("content-length") || 0) > 100000)
      throw new Error("invalid_input");
    const { command, args } = await req.json();
    const context = await authenticatedClient();
    const { db } = context;
    if (typeof command !== "string" || !args || typeof args !== "object")
      throw new Error("invalid_input");
    if (['create_maintenance_request','change_maintenance_request'].includes(command)
      && !maintenanceCommandValid(command,args)) throw new Error('invalid_input');
    if (command === 'create_production_request' && Object.keys(args).some((key) =>
      !['factory', 'request_name', 'request_priority', 'request_required_by', 'request_notes', 'request_items'].includes(key)))
      throw new Error('invalid_input');
    if (command === "save_record") {
      if (
        ![
          "factory",
          "lines",
          "centers",
          "work_center_categories",
          "orders",
          "products",
          "downtime",
          "roles",
        ].includes(args.resource)
      )
        throw new Error("invalid_resource");
      await authorize(
        args.factory,
        args.resource === "products"
          ? "orders"
          : args.resource === "work_center_categories"
            ? "centers"
            : args.resource,
        args.id ? "edit" : "create",
        context,
      );
    } else if (["change_status", "stop_machine", "update_downtime",
      "set_downtime_initial"].includes(command)) {
      const { data: allowed } = await db.rpc("can_access", {
        factory: args.factory,
        module: "machine_status",
        action: "edit",
      });
      if (!allowed) {
        if (command === "set_downtime_initial") {
          const { data: centersAllowed } = await db.rpc("can_access", {
            factory: args.factory, module: "centers", action: "edit",
          });
          if (!centersAllowed) await authorize(args.factory, "downtime", "edit", context);
        } else await authorize(args.factory,
          command === "update_downtime" ? "downtime" : "centers", "edit", context);
      }
    } else if (command === 'change_maintenance_request') {
      // The scoped RPC authorizes the manager OR the current assignee for progress only.
      await authorize(args.factory,'factory','view',context);
    } else if (rpcModules[command]) {
      for (const [module, action] of rpcModules[command])
        await authorize(args.factory, module, action, context);
    } else if (
      ![
        "create_factory",
        "request_membership",
        "open_platform_factory",
      ].includes(command)
    )
      throw new Error("invalid_command");
    if (command === "save_production_loss_estimate") {
      // The Edge Function reads authoritative event/context data and invokes a
      // service-only persistence RPC. Never forward browser arithmetic.
      if (Object.keys(args).sort().join(",") !== "event,factory" ||
        typeof args.factory !== "string" || typeof args.event !== "string")
        throw new Error("invalid_input");
      const { data, error } = await db.functions.invoke(
        "save-production-loss-estimate", { body: {
          factory: args.factory, event: args.event,
        } });
      if (error) {
        const response = error.context;
        const detail = response instanceof Response ? await response.json()
          .catch(() => ({})) : {};
        return NextResponse.json({
          error: commandErrors[detail.error] || "error",
        }, { status: 400 });
      }
      return NextResponse.json({ data: data?.id });
    }
    const { data, error } = await db.rpc(command, args);
    if (data?.error)
      return NextResponse.json(
        {
          error:
            command === "request_membership"
              ? joinErrors[data.error] || "joinError"
              : commandErrors[data.error] || "error",
        },
        { status: 400 },
      );
    if (error) {
      console.warn("factory_command_failed", { command, code: error.code });
      return NextResponse.json(
        {
          error:
            error.code === "42501"
              ? "permissionError"
              : error.code === "23505"
                ? "duplicateRecord"
                : error.code === "23514"
                  ? "invalidValues"
                  : commandErrors[error.message] || "error",
        },
        { status: 400 },
      );
    }
    return NextResponse.json({ data });
  } catch (e) {
    return NextResponse.json(safeError(e), { status: 400 });
  }
}
