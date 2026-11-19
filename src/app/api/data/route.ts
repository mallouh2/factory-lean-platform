import { NextRequest, NextResponse } from "next/server";
import {hydrateInterruptedOrders} from '@/services/production-execution';
import {
  authenticatedClient,
  authorize,
  verifyOrigin,
  safeError,
} from "@/services/authorization";
import { hasEveryDefinedPermission } from "@/utils/permission-preview.mjs";
import { recordingFailure,exactRecordingPayload,recordingFetch } from '@/utils/production-recording-v3.mjs';
import { maintenanceCommandValid } from '@/utils/maintenance.mjs';
import { maintenanceStopCommands, maintenanceStopCommandValid } from '@/utils/maintenance-stops.mjs';
import { maintenancePlanningCommandValid, maintenancePlanningPermissions } from '@/utils/maintenance-planning.mjs';
import { supplyCommandValid } from '@/utils/supply-contract.mjs';
import { packageCommands, packageCommandValid } from '@/utils/permission-packages.mjs';
import { leanCommands, leanCommandValid, leanRequiredPermission } from '@/utils/lean-contract.mjs';
import { qualityCommandValid, sourceCommandValid,qualityRequiredPermissions,sourceRequiredPermissions } from '@/utils/quality-contract.mjs';
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
    // Independent authorized snapshot sections do not need to wait for each
    // other's network/database round trip. Keep the same all-or-error response.
    const factoryId=data?.factory?.id;
    const recordingAllowed=Boolean(factoryId&&data.permissions?.includes('orders:view'));
    const shiftsAllowed=Boolean(factoryId&&(recordingAllowed||data.permissions?.includes('settings:view')));
    stage='snapshot_hydration';
    const [recordingResult,shiftsResult,contextResult,executionOrders]=await Promise.all([
      recordingAllowed?db.rpc('production_recording_units',{factory:factoryId}):null,
      shiftsAllowed?db.from('production_shifts').select('*').eq('factory_id',factoryId).order('created_at'):null,
      shiftsAllowed?db.rpc('production_shift_context',{factory:factoryId}):null,
      recordingAllowed?hydrateInterruptedOrders(db,factoryId,data.tables.production_orders||[]):Promise.resolve(data.tables.production_orders),
    ]);
    if(executionOrders)data.tables.production_orders=executionOrders;
    if (recordingResult) {
      stage = "production_recording_units";
      const { data: recording, error: recordingError } = recordingResult;
      if (recordingError) throw recordingError;
      data.tables.production_recording_units = recording.units;
      data.tables.production_technicians = recording.technicians;
    }
    if (shiftsResult&&contextResult) {
      stage = "production_shifts";
      const {data: shifts,error: shiftError}=shiftsResult;
      if(shiftError) throw shiftError;
      data.tables.production_shifts=shifts;
      stage = 'production_shift_context';
      const {data: context,error: contextError}=contextResult;
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
  machine_impact_conflict:'machine_impact_conflict',execution_no_active_work:'execution_no_active_work',execution_line_idle:'execution_line_idle',execution_machine_stopped:'execution_machine_stopped',
  material_use_preparation_workflow:'material_use_preparation_workflow',
  maintenance_active_stop:'maintenanceActiveStop',maintenance_stop_scope:'maintenanceStopScope',
  maintenance_stop_window:'maintenanceStopWindow',maintenance_stop_conflict:'maintenanceStopStale',
  quality_quantity:'qualityInvalidQuantity',quality_weight:'qualityWeightRequired',quality_unavailable:'qualityUnavailable',quality_reserved:'qualityReserved',quality_reason:'qualityReasonRequired',quality_duplicate_reason:'qualityReasonDuplicate',quality_shortfall:'qualityShortfall',quality_reversal_unavailable:'qualityReversalUnavailable',
  source_identity:'sourceIdentity',source_selection_required:'sourceSelectionRequired',source_quantity:'sourceQuantity',source_unavailable:'sourceUnavailable',source_committed:'sourceCommitted',source_conservation:'sourceStockChanged',source_correction_unavailable:'sourceUnavailable',
  lean_invalid:'leanInvalid',lean_conflict:'leanConflict',lean_closed:'leanClosed',lean_incomplete:'leanIncomplete',lean_baseline_missing:'leanBaselineMissing',lean_startup_required:'leanStartupRequired',lean_link_invalid:'leanLinkInvalid',lean_link_cause:'leanLinkCause',lean_insufficient_exposure:'leanInsufficientExposure',lean_scrap_kg_only:'leanScrapKgOnly',lean_comparison_product:'leanComparisonProduct',
  permission_package_conflict: 'packageConflict',
  supply_invalid: 'supplyInvalid',
  supply_conflict: 'supplyConflict',
  supply_duplicate: 'supplyDuplicate',
  supply_state: 'supplyState',
  supply_reason: 'supplyReason',
  supply_insufficient: 'supplyInsufficient',
  warehouse_stock_changed: 'inventoryStockChanged',
  warehouse_confirmation_required: 'inventoryConfirmationRequired',
  maintenance_invalid: 'maintenanceInvalid',
  maintenance_machine: 'maintenanceInvalidMachine',
  maintenance_downtime: 'maintenanceInvalidDowntime',
  maintenance_assignee: 'maintenanceInvalidAssignee',
  maintenance_state: 'maintenanceInvalidState',
  maintenance_conflict: 'maintenanceConflict',
  maintenance_preview_stale: 'mpPreviewStale',
  maintenance_preview_required: 'mpPreviewRequired',
  maintenance_preview_incomplete: 'mpIncomplete',
  maintenance_note: 'maintenanceNoteRequired',
  maintenance_preferred_reason: 'mpOutsidePreferred',
  maintenance_details_locked: 'mpReservationDetailsLocked',
  maintenance_missing: 'noResults',
  maintenance_existing: 'maintenanceExistingProblem',
  maintenance_independent_verifier: 'maintenanceIndependentVerifier',
  maintenance_planning_inactive: 'maintenancePlanningInactive',
  maintenance_capacity_reserved: 'maintenanceCapacityReserved',
  maintenance_production_conflict: 'maintenanceProductionConflict',
  maintenance_unknown_window: 'maintenanceUnknownWindow',
  maintenance_configuration_unknown: 'maintenanceConfigurationUnknown',
  maintenance_configuration_changed: 'maintenanceConfigurationChanged',
  maintenance_execution_window_unknown: 'maintenanceUnknownWindow',
  maintenance_transfer_unresolved: 'maintenanceTransferUnresolved',
  maintenance_approval_required: 'maintenanceApprovalRequired',
  maintenance_early_start: 'maintenanceEarlyStart',
  maintenance_late_start: 'maintenanceLateStart',
  maintenance_machine_not_ready: 'maintenanceMachineNotReady',
  maintenance_unschedule_required: 'maintenanceUnscheduleRequired',
  internal_reason_required: 'internalReasonRequired',
  fulfillment_invalid: 'fulfillmentInvalid',
  fulfillment_product: 'fulfillmentProduct',
  fulfillment_state: 'fulfillmentState',
  fulfillment_hold: 'fulfillmentHold',
  fulfillment_not_ready: 'fulfillmentNotReady',
  pooled_dispatch_unavailable:'pooledDispatchUnavailable',
  planning_material_committed:'planningMaterialCommitted',
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
  sales_promise_read_only: "salesPromiseReadOnly",
  stock_opening_exists: "stockOpeningExists",
  fulfillment_stock_identity: "fulfillmentStockIdentity",
  fulfillment_source_decision: "fulfillmentSourceDecision",
  output_work_capability: 'planningIncompatibleLine',
  output_work_not_ready: 'compNotReady',
  output_quality_hold: 'planningQualityHold',
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
  quality_command:[['factory','view']],source_stock_command:[['factory','view']],
  record_lean_production:[['orders','edit'],['orders','view']],
  correct_lean_production:[['orders','edit'],['orders','view']],
  lean_command:[['factory','view']],
  save_permission_package: [['roles','edit']],
  set_member_permission_packages: [['roles','edit']],
  set_member_direct_permissions: [['roles','edit']],
  approve_member_packages: [['employees','approve'],['roles','edit']],
  create_maintenance_request: [['factory','view'],['maintenance','create']],
  create_sales_order: [['sales_orders', 'create']],
  approve_sales_order: [['sales_orders', 'approve']],
  change_sales_order: [['sales_orders', 'edit']],
  dispatch_sales_order: [['warehouse', 'issue']],
  dispatch_sales_quantity: [['warehouse', 'issue']],
  configure_product_stock: [['warehouse', 'edit']],
  confirm_warehouse_replenishment: [['warehouse', 'edit']],
  configure_warehouse_material: [['warehouse', 'edit']],
  configure_warehouse_product: [['warehouse', 'edit']],
  receive_warehouse_stock: [['warehouse', 'edit']],
  create_warehouse_material: [['warehouse', 'edit']],
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
  let v3Recording=false;
  let maintenancePlanning=false;
  try {
    verifyOrigin(req);
    if (Number(req.headers.get("content-length") || 0) > 100000)
      throw new Error("invalid_input");
    const raw = await req.text();
    const { command, args } = JSON.parse(raw);
    maintenancePlanning=command==='maintenance_planning_command';
    // Transport opt-in also preserves existing WIP/independent inputs. It does
    // not supply recording_context or grant late admission; SQL owns both.
    v3Recording=command==='record_lean_production' && args?.payload &&
      (Object.hasOwn(args.payload,'recording_context') || req.headers.get('x-factory-recording')==='3');
    const context = await authenticatedClient(v3Recording?recordingFetch():undefined);
    const { db } = context;
    if (typeof command !== "string" || !args || typeof args !== "object")
      throw new Error("invalid_input");
    if(command==='quality_command'&&!qualityCommandValid(args))throw new Error('invalid_input');
    if(command==='source_stock_command'&&!sourceCommandValid(args))throw new Error('invalid_input');
    if(command==='quality_command'||command==='source_stock_command'){
      for(const [module,action] of (command==='quality_command'?qualityRequiredPermissions(args.operation):sourceRequiredPermissions(args.operation)))await authorize(args.factory,module,action,context);
    }
    if (packageCommands.includes(command) && !packageCommandValid(command,args)) throw new Error('invalid_input');
    if (leanCommands.includes(command) && !leanCommandValid(command,args)) throw new Error('invalid_input');
    if (command==='lean_command') { const [module,action]=leanRequiredPermission(args.operation); await authorize(args.factory,module,action,context); }
    if (['create_maintenance_request','change_maintenance_request'].includes(command)
      && !maintenanceCommandValid(command,args)) throw new Error('invalid_input');
    if (command==='maintenance_planning_command' && !maintenancePlanningCommandValid(args)) throw new Error('invalid_input');
    if (maintenanceStopCommands.includes(command) && !maintenanceStopCommandValid(command,args)) throw new Error('invalid_input');
    if (['supply_command','define_manufactured_product'].includes(command)&&!supplyCommandValid(command,args)) throw new Error('invalid_input');
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
    } else if (maintenanceStopCommands.includes(command)) {
      await authorize(args.factory,'factory','view',context);
      if(command==='correct_maintenance_stop') {
        await authorize(args.factory,'maintenance','edit',context);await authorize(args.factory,'downtime','edit',context);
      } else {
        await authorize(args.factory,'maintenance','view',context);
        const {data:allowed}=await db.rpc('can_access',{factory:args.factory,module:'machine_status',action:'edit'});
        if(!allowed) await authorize(args.factory,'centers','edit',context);
      }
    } else if (["change_status", "stop_machine", "stop_machine_with_impact", "update_downtime",
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
    } else if (command === 'supply_command' || command === 'define_manufactured_product') {
      // The RPC independently checks the specific action and original requester.
      await authorize(args.factory,'factory','view',context);
    } else if (command === 'maintenance_planning_command') {
      await authorize(args.factory,'factory','view',context);
      for (const [module,action] of maintenancePlanningPermissions(args.operation)) await authorize(args.factory,module,action,context);
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
        }, { status: detail.error === "loss_estimate_context_mismatch" || detail.error === "loss_estimate_locked"
          ? 409 : detail.error === "permission_denied" ? 403 : detail.error === "loss_estimate_incomplete" ? 422 : 400 });
      }
      return NextResponse.json({ data: data?.id });
    }
    if(v3Recording)exactRecordingPayload(raw,args.payload);
    const { data, error } = await db.rpc(command, args);
    if (v3Recording) {
      if(error) {
        const {status,...body}=recordingFailure(error);
        return NextResponse.json(body,{status,headers:{'Cache-Control':'private, no-store'}});
      }
      return NextResponse.json({data},{headers:{'Cache-Control':'private, no-store'}});
    }
    if (maintenancePlanning && (error?.code==='42501' || error?.message==='permission_denied' || data?.error==='permission_denied'))
      return NextResponse.json({error:'permissionError'}, {status:403});
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
    if (error && command === 'maintenance_planning_command' && error.code === '40001') {
      return NextResponse.json({error:'mpPreviewStale',conflict:'STALE_CONTEXT'}, {status:409,headers:{'Cache-Control':'private, no-store'}});
    }
    if(error && command==='start_product_item' && error.message==='production_material_not_ready') {
      return NextResponse.json({error:'productionMaterialNotReady'},
        {status:409,headers:{'Cache-Control':'private, no-store'}});
    }
    if(error && command==='start_product_item' && error.message==='execution_physical_not_ready') {
      let condition:Record<string,unknown>={};
      try{condition=JSON.parse(error.details || '{}');}catch{ /* Keep internal diagnostics out of the response. */ }
      return NextResponse.json({error:'productionPhysicalNotReady',reason:condition.reason,machine:condition.machine},
        {status:409,headers:{'Cache-Control':'private, no-store'}});
    }
    if(error && command==='start_product_item' && error.code==='40001') {
      return NextResponse.json({error:'productionQueueChanged'},{status:409,headers:{'Cache-Control':'private, no-store'}});
    }
    if (error && maintenanceStopCommands.includes(command) && error.code==='40001') {
      return NextResponse.json({error:'maintenanceStopStale'}, {status:409,headers:{'Cache-Control':'private, no-store'}});
    }
    if(error&&['output_paused','output_enrollment_required','output_carryover_unsupported'].includes(error.message)){const {status,...body}=recordingFailure(error);return NextResponse.json(body,{status,headers:{'Cache-Control':'private, no-store'}});}
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
    if(v3Recording) {
      const {status,...body}=recordingFailure(e);
      return NextResponse.json(body,{status,headers:{'Cache-Control':'private, no-store'}});
    }
    const maintenanceStatus=maintenancePlanning && e instanceof Error
      ? e.message==='permission_denied' ? 403 : e.message==='unauthorized' ? 401 : 400
      : 400;
    return NextResponse.json(safeError(e), { status: maintenanceStatus });
  }
}
