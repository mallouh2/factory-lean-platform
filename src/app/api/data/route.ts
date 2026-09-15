import { NextRequest, NextResponse } from "next/server";
import {
  authenticatedClient,
  authorize,
  verifyOrigin,
  safeError,
} from "@/services/authorization";
export async function GET(req: NextRequest) {
  try {
    const { db, user } = await authenticatedClient();
    const {data,error} = await db.rpc("factory_snapshot", {factory:req.nextUrl.searchParams.get("factory") || null});
    if(error) throw error;
    return NextResponse.json({...data,user:{id:user.id,email:user.email}});
  } catch(e) { return NextResponse.json(safeError(e),{status:e instanceof Error && e.message === "unauthorized" ? 401 : 403}); }
}
const rpcModules: Record<string, [string, string]> = {
  set_daily_target: ["orders", "edit"],
  record_output: ["orders", "edit"],
  record_access: ["reports", "export"],
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
    const context = await authenticatedClient();
    const {db}=context;
    if (typeof command !== "string" || !args || typeof args !== "object")
      throw new Error("invalid_input");
    if (command === "save_record") {
      if (
        ![
          "factory",
          "lines",
          "centers",
          "orders",
          "products",
          "downtime",
          "roles",
        ].includes(args.resource)
      )
        throw new Error("invalid_resource");
      await authorize(args.factory, args.resource === "products" ? "orders" : args.resource, args.id ? "edit" : "create",context);
    } else if (command === "change_status") {
      const {data: allowed} = await db.rpc("can_access",{factory:args.factory,module:"machine_status",action:"edit"});
      if(!allowed) await authorize(args.factory,"centers","edit",context);
    } else if (rpcModules[command]) {
      const [module, action] = rpcModules[command];
      await authorize(args.factory, module, action,context);
    } else if (!["create_factory", "request_membership"].includes(command))
      throw new Error("invalid_command");
    const { data, error } = await db.rpc(command, args);
    if (data?.error) return NextResponse.json({error: "joinError"}, {status:400});
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
