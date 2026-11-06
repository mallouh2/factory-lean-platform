import { NextRequest, NextResponse } from "next/server";
import { authenticatedClient } from "@/services/authorization";
import { historyError, historyPage, historyUuid } from "@/services/history-response";
import { collectHistoryPages, deliverLossReview } from "@/utils/loss-review-delivery.mjs";

export async function GET(req: NextRequest) {
  try {
    const { db } = await authenticatedClient();
    const params = req.nextUrl.searchParams;
    const factory = historyUuid(params.get("factory"));
    async function read(kind: string, event: string | null, page = 1) {
      // Each call rechecks factory:view + downtime:view and retains table RLS.
      const { data, error } = await db.rpc("production_loss_history", { factory, kind, event, page });
      if (error) throw error;
      if (kind === "detail") {
        const maintenance = await db.rpc("production_loss_maintenance_context", { factory, event });
        if (maintenance.error) throw maintenance.error;
        return { ...data, maintenance: maintenance.data };
      }
      if (kind === "observations") {
        const records = await Promise.all(data.rows.map(async (row: { event: { id: string } }) => {
          const maintenance = await db.rpc("production_loss_maintenance_context", { factory, event: row.event.id });
          if (maintenance.error) throw maintenance.error;
          return { ...row, maintenance: maintenance.data };
        }));
        return { ...data, rows: records };
      }
      return data;
    }
    const event = params.has("event") ? historyUuid(params.get("event")) : null;
    const selected = event ? await read("detail", event) : null;
    const data = event ? await deliverLossReview(selected,
      selected.saved ? [] : await collectHistoryPages((page: number) => read("observations", event, page)),
      (id: string) => collectHistoryPages((page: number) => read("contexts", id, page)))
      : await read("events", null, historyPage(params.get("page")));
    return NextResponse.json(data, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return historyError(error); }
}
