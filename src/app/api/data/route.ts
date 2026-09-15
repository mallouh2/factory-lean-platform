import { NextRequest, NextResponse } from "next/server";
import {
  authenticatedClient,
  authorize,
  verifyOrigin,
  safeError,
} from "@/services/authorization";
const modules = [
  "dashboard",
  "factory",
  "lines",
  "centers",
  "orders",
  "downtime",
  "reports",
  "employees",
  "roles",
  "settings",
  "support",
  "audit",
];
const tables = [
  "areas",
  "production_lines",
  "work_centers",
  "products",
  "production_orders",
  "downtime_reasons",
  "status_events",
  "downtime_events",
  "memberships",
  "roles",
  "role_permissions",
  "support_access",
  "audit_logs",
  "machine_statuses",
  "oee_observations",
];
export async function GET(req: NextRequest) {
  try {
    const { db, user } = await authenticatedClient();
    const { data: membership, error } = await db
      .from("memberships")
      .select("*")
      .eq("user_id", user.id)
      .maybeSingle();
    if (error) throw error;
    const { data: supportFactories } = await db
      .from("support_access")
      .select("*")
      .eq("user_id", user.id);
    const selected = req.nextUrl.searchParams.get("factory");
    const factoryId =
      membership?.status === "approved" ? membership.factory_id : selected;
    const base = {
      user: { id: user.id, email: user.email },
      membership,
      permissions: [],
      factory: null,
      tables: {},
      supportFactories: supportFactories || [],
      fetchedAt: new Date().toISOString(),
    };
    if (!factoryId) return NextResponse.json(base);
    await authorize(factoryId, "factory", "view");
    const { data: factory, error: factoryError } = await db
      .from("factories")
      .select("*")
      .eq("id", factoryId)
      .single();
    if (factoryError) throw factoryError;
    const { data: checks, error: permissionError } = await db.rpc(
      "access_matrix",
      { factory: factoryId },
    );
    if (permissionError) throw permissionError;
    const result = await Promise.all(
      tables.map(async (table) => {
        let query = db.from(table).select("*");
        if (table !== "machine_statuses")
          query = query.eq("factory_id", factoryId);
        if (["audit_logs", "status_events"].includes(table))
          query = query.order("created_at", { ascending: false });
        const { data, error } = await query.limit(1000);
        if (error) throw error;
        return [table, data || []];
      }),
    );
    return NextResponse.json({
      ...base,
      factory,
      permissions: checks || [],
      tables: Object.fromEntries(result),
    });
  } catch (e) {
    return NextResponse.json(safeError(e), {
      status: e instanceof Error && e.message === "unauthorized" ? 401 : 403,
    });
  }
}
const rpcModules: Record<string, [string, string]> = {
  change_status: ["centers", "edit"],
  manage_member: ["employees", "approve"],
  get_join_code: ["settings", "edit"],
  update_settings: ["settings", "edit"],
  set_permissions: ["roles", "edit"],
  set_support: ["support", "edit"],
};
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    if (Number(req.headers.get("content-length") || 0) > 100000)
      throw new Error("invalid_input");
    const { command, args } = await req.json();
    const { db } = await authenticatedClient();
    if (typeof command !== "string" || !args || typeof args !== "object")
      throw new Error("invalid_input");
    if (command === "save_record") {
      if (
        ![
          "factory",
          "lines",
          "centers",
          "orders",
          "downtime",
          "roles",
        ].includes(args.resource)
      )
        throw new Error("invalid_resource");
      await authorize(args.factory, args.resource, args.id ? "edit" : "create");
    } else if (rpcModules[command]) {
      const [module, action] = rpcModules[command];
      await authorize(args.factory, module, action);
    } else if (!["create_factory", "join_factory"].includes(command))
      throw new Error("invalid_command");
    const { data, error } = await db.rpc(command, args);
    if (error) {
      console.warn("factory_command_failed", { command, code: error.code });
      return NextResponse.json(
        { error: error.code === "42501" ? "permissionError" : "error" },
        { status: 400 },
      );
    }
    return NextResponse.json({ data });
  } catch (e) {
    return NextResponse.json(safeError(e), { status: 400 });
  }
}
