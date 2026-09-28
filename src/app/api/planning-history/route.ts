import { NextRequest, NextResponse } from "next/server";
import { authenticatedClient, authorize, safeError } from "@/services/authorization";

export async function GET(req: NextRequest) {
  try {
    const factory = req.nextUrl.searchParams.get("factory") || "";
    const item = req.nextUrl.searchParams.get("item") || "";
    if (!/^[0-9a-f-]{36}$/i.test(factory) || !/^[0-9a-f-]{36}$/i.test(item))
      throw new Error("invalid_input");
    const context = await authenticatedClient();
    await authorize(factory, "orders", "view", context);
    const { data, error } = await context.db.from("production_plan_revisions")
      .select("revision_no,event,before_line_id,before_start,before_finish,after_line_id,after_start,after_finish,reason_code,reason_note,changed_by_name,changed_at")
      .eq("factory_id", factory).eq("item_id", item).order("revision_no", { ascending: true });
    if (error) throw error;
    return NextResponse.json({ revisions: data || [] }, { headers: { "Cache-Control": "no-store" } });
  } catch (cause) {
    return NextResponse.json(safeError(cause), { status: 403 });
  }
}
