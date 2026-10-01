import { NextRequest, NextResponse } from "next/server";
import { authenticatedClient } from "@/services/authorization";
import { historyError, historyPage, historyUuid } from "@/services/history-response";

export async function GET(req: NextRequest) {
  try {
    const { db } = await authenticatedClient();
    const params = req.nextUrl.searchParams;
    const search = params.get("search") || "";
    if (search.length > 2000) throw { code: "22023" };
    // RPC requires factory:view + audit:view; SECURITY INVOKER also enforces RLS.
    const { data, error } = await db.rpc("audit_history", {
      factory: historyUuid(params.get("factory")), search, page: historyPage(params.get("page")),
    });
    if (error) throw error;
    return NextResponse.json(data, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return historyError(error); }
}
