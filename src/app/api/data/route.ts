import { NextRequest, NextResponse } from "next/server";
import {
  authenticatedClient,
  authorize,
  verifyOrigin,
  safeError,
} from "@/services/authorization";
import { hasEveryDefinedPermission } from "@/utils/permission-preview.mjs";
export async function GET(req: NextRequest) {
  try {
    const { db, user } = await authenticatedClient();
    const { data, error } = await db.rpc("factory_snapshot", {
      factory: req.nextUrl.searchParams.get("factory") || null,
    });
    if (error) throw error;
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
    return NextResponse.json(safeError(e), {
      status: e instanceof Error && e.message === "unauthorized" ? 401 : 403,
    });
  }
}
const commandErrors: Record<string, string> = {
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
};
/** request_membership reports failures as JSONB values instead of raising; map them to specific client keys. */
const joinErrors: Record<string, string> = {
  invalid_join_code: "invalidJoinCode",
  rate_limited: "rateLimited",
  already_joined: "alreadyJoined",
};
/** Pre-checks mirror the require_permission calls inside each RPC; the database remains authoritative. */
const rpcModules: Record<string, [string, string][]> = {
  create_production_request: [["orders", "create"]],
  plan_product_item: [["orders", "edit"]],
  revise_product_plan: [["orders", "edit"]],
  set_plan_lock: [["orders", "edit"]],
  start_product_item: [["orders", "edit"]],
  finish_product_item: [["orders", "edit"]],
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
    } else if (["change_status", "update_downtime"].includes(command)) {
      const { data: allowed } = await db.rpc("can_access", {
        factory: args.factory,
        module: "machine_status",
        action: "edit",
      });
      if (!allowed)
        await authorize(
          args.factory,
          command === "update_downtime" ? "downtime" : "centers",
          "edit",
          context,
        );
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
    const { data, error } = await db.rpc(command, args);
    if (data?.error)
      return NextResponse.json(
        {
          error:
            command === "request_membership"
              ? joinErrors[data.error] || "joinError"
              : "joinError",
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
