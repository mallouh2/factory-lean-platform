import { NextRequest, NextResponse } from "next/server";
import { authenticatedClient, authorize } from "@/services/authorization";
import { historyError, historyPage, historyUuid } from "@/services/history-response";
import { collectHistoryPages, deliverLossReview } from "@/utils/loss-review-delivery.mjs";
import type { Row } from "@/types";

type Client = Awaited<ReturnType<typeof authenticatedClient>>["db"];

async function relatedMaintenance(db: Client, factory: string, event: string, schedule?: string) {
  const direct = await db.from("maintenance_requests").select("id,code")
    .eq("factory_id", factory).eq("downtime_id", event).order("requested_at", { ascending: false }).limit(1);
  if (direct.data?.[0] || !schedule) return direct.data?.[0] || null;
  const plan = await db.from("maintenance_schedules").select("maintenance_request_id")
    .eq("factory_id", factory).eq("id", schedule).limit(1);
  const id = plan.data?.[0]?.maintenance_request_id;
  if (!id) return null;
  const request = await db.from("maintenance_requests").select("id,code")
    .eq("factory_id", factory).eq("id", id).limit(1);
  return request.data?.[0] || null;
}

async function readRows(readPage: (from: number, to: number) =>
  PromiseLike<{ data: Row[] | null; error: unknown }>) {
  const rows: Row[] = [];
  const size = 250;
  for (let from = 0; ; from += size) {
    const { data, error } = await readPage(from, from + size - 1);
    if (error) throw error;
    rows.push(...(data || []));
    if (!data || data.length < size) return rows;
  }
}

async function linkedScrap(db: Client, factory: string, event: Row) {
  const access = await db.rpc("can_access", { factory, module: "lean", action: "view" });
  if (access.error || access.data !== true) return { state: "unavailable" };
  const links = await db.from("lean_scrap_events")
    .select("entry_id,approved_cause_id,reviewed_at")
    .eq("factory_id", factory).eq("downtime_id", event.id).limit(251);
  if (links.error) return { state: "unavailable" };
  if (!links.data.length) return { state: "unlinked" };
  if (links.data.length > 250 || !event.approved_at || !event.approved_cause_id ||
    links.data.some(link => link.approved_cause_id !== event.approved_cause_id || !link.reviewed_at))
    return { state: "unverified" };

  // Read the same reviewed occurrence used in Lean. It verifies review freshness
  // against source corrections. The explicit links above rule out its manual fallback.
  const start = Date.parse(String(event.started_at));
  if (!Number.isFinite(start)) return { state: "unverified" };
  const result = await db.rpc("lean_read", { factory, query: {
    mode: "analysis_occurrences", from: new Date(start).toISOString(),
    to: new Date(start + 1000).toISOString(), machine_id: event.work_center_id,
    cause_id: event.approved_cause_id, page: 1,
  } });
  if (result.error) return { state: "unavailable" };
  const occurrence = (result.data?.rows || []).find((row: Row) =>
    row.mechanism === "downtime" && row.event_id === event.id);
  if (occurrence?.scrap_kg == null) return { state: "unverified" };

  const ids = [...new Set(links.data.map(link => link.entry_id))];
  const entries = await db.from("production_entries").select("id,effective_scrap_kg,effective_startup_kg,lean_startup_id")
    .eq("factory_id", factory).in("id", ids);
  const kg = Number(occurrence.scrap_kg);
  const startup = !entries.error && entries.data.length === ids.length &&
    entries.data.every(entry => entry.effective_scrap_kg != null && entry.effective_startup_kg != null &&
      Number(entry.effective_startup_kg) <= Number(entry.effective_scrap_kg) &&
      (Number(entry.effective_startup_kg) === 0 || entry.lean_startup_id)) &&
    Math.abs(entries.data.reduce((sum, entry) => sum + Number(entry.effective_scrap_kg), 0) - kg) < 0.000001
    ? entries.data.reduce((sum, entry) => sum + Number(entry.effective_startup_kg), 0) : null;
  return { state: "recorded", kg, startup, entries: ids.length };
}

export async function GET(req: NextRequest) {
  try {
    const context = await authenticatedClient();
    const { db } = context;
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
    let data;
    if (event) {
      const selected = await read("detail", event);
      const [corrections, scrap, candidates, relatedRequest] = await Promise.all([
        readRows((from, to) => db.from("downtime_classification_corrections").select("*")
          .eq("factory_id", factory).eq("event_id", event)
          .order("corrected_at", { ascending: false }).order("id", { ascending: false }).range(from, to)),
        linkedScrap(db, factory, selected.event),
        selected.saved ? [] : collectHistoryPages((page: number) => read("observations", event, page)),
        relatedMaintenance(db, factory, event, selected.maintenance?.evidence?.schedule_id),
      ]);
      data = { ...await deliverLossReview(selected, candidates,
        (id: string) => collectHistoryPages((page: number) => read("contexts", id, page))),
        corrections, scrap, relatedRequest };
    } else if (params.has("related")) {
      await Promise.all([authorize(factory, "factory", "view", context),
        authorize(factory, "downtime", "view", context)]);
      const id = historyUuid(params.get("related"));
      const evidence = await db.rpc("production_loss_maintenance_context", { factory, event: id });
      if (evidence.error) throw evidence.error;
      data = { relatedRequest: await relatedMaintenance(db, factory, id, evidence.data?.evidence?.schedule_id) };
    } else if (params.get("view") === "register") {
      await Promise.all([authorize(factory, "factory", "view", context),
        authorize(factory, "downtime", "view", context)]);
      const [rows, corrections] = await Promise.all([
        readRows((from, to) => db.from("downtime_events").select(
          `id,work_center_id,line_id,order_id,started_at,ended_at,stop_nature,planned_activity,
          blocking_at_start,notes,initial_note,initial_entered_by,created_by,reason_id,
          approved_cause_id,approved_at,approved_by,engineering_note,retroactive`)
          .eq("factory_id", factory).order("started_at", { ascending: false })
          .order("id").range(from, to)),
        readRows((from, to) => db.from("downtime_classification_corrections").select("id,event_id")
          .eq("factory_id", factory).order("id").range(from, to)),
      ]);
      data = { rows, correctedIds: [...new Set(corrections.map(row => row.event_id))] };
    } else {
      data = await read("events", null, historyPage(params.get("page")));
    }
    return NextResponse.json(data, { headers: { "Cache-Control": "private, no-store" } });
  } catch (error) { return historyError(error); }
}
