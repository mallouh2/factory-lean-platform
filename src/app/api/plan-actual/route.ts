import { NextRequest, NextResponse } from "next/server";
import { authenticatedClient, authorize } from "@/services/authorization";
import { historyError, historyUuid } from "@/services/history-response";
import type { Row } from "@/types";

const orderColumns = "id,code,request_id,product_id,line_id,start_time,expected_finish,actual_start,actual_finish";
const revisionColumns = "item_id,revision_no,event,before_line_id,before_start,before_finish,after_line_id,after_start,after_finish,reason_code,reason_note,changed_by_name,changed_at";
const headers = { "Cache-Control": "private, no-store" };
const day = 86_400_000;
const batchSize = 8;

async function timeline(db: Awaited<ReturnType<typeof authenticatedClient>>["db"],
  factory: string, orders: Row[], from: string, to: string) {
  const plans = new Map<string, Row[]>();
  const demos = new Set<string>();
  for (let offset = 0; offset < orders.length; offset += 100) {
    const chunk = orders.slice(offset, offset + 100);
    const [rows, requests] = await Promise.all([
      readRows((a, b) => db.from("production_plan_revisions").select(revisionColumns)
        .eq("factory_id", factory).in("item_id", chunk.map(order => String(order.id)))
        .order("item_id").order("revision_no").range(a, b)),
      db.from("production_requests").select("id,name").eq("factory_id", factory)
        .in("id", [...new Set(chunk.map(order => String(order.request_id)))]),
    ]);
    if (requests.error) throw requests.error;
    for (const request of requests.data || []) {
      if (String(request.name).startsWith("[F37 DEMO] ")) demos.add(String(request.id));
    }
    for (const row of rows) {
      const id = String(row.item_id);
      const revisions = plans.get(id) || [];
      revisions.push(row);
      plans.set(id, revisions);
    }
  }
  // Private execution history is accessible through the existing authenticated reader.
  // Only orders with overlapping recorded execution bounds need that lookup.
  const histories = new Map<string, Row[]>();
  const executed = orders.filter(order => order.actual_start && Date.parse(String(order.actual_start)) < Date.parse(to) &&
    (!order.actual_finish || Date.parse(String(order.actual_finish)) >= Date.parse(from)));
  for (let offset = 0; offset < executed.length; offset += batchSize) {
    await Promise.all(executed.slice(offset, offset + batchSize).map(async order => {
      const item = String(order.id);
      const result = await db.rpc("production_execution_context", { factory, item });
      if (result.error) throw result.error;
      const overlapping = ((result.data?.history || []) as Row[]).filter(run =>
        Date.parse(String(run.started_at)) < Date.parse(to) &&
        (!run.ended_at || Date.parse(String(run.ended_at)) >= Date.parse(from)));
      histories.set(item, overlapping.map(run => ({
        id: run.id, line_id: run.line_id, state: run.state, started_at: run.started_at,
        ended_at: run.ended_at, reason: run.reason, start_reason: run.start_reason,
      })));
    }));
  }
  return orders.map(order => {
    const revisions = plans.get(String(order.id)) || [];
    return { order, demo: demos.has(String(order.request_id)),
      plan: revisions.length > 1 ? [revisions[0], revisions.at(-1)] : revisions,
      history: histories.get(String(order.id)) || [] };
  });
}

async function readRows(read: (start: number, end: number) =>
  PromiseLike<{ data: Row[] | null; error: unknown }>) {
  const size = 200;
  const rows: Row[] = [];
  for (let start = 0; start < 2000; start += size) {
    const result = await read(start, start + size - 1);
    if (result.error) throw result.error;
    const page = result.data || [];
    rows.push(...page);
    if (page.length < size) return rows;
  }
  throw { code: "F3701" };
}

export async function GET(req: NextRequest) {
  try {
    const params = req.nextUrl.searchParams;
    for (const key of params.keys()) {
      if (!["factory", "item", "from", "to"].includes(key) || params.getAll(key).length !== 1) {
        throw { code: "22023" };
      }
    }
    const factory = historyUuid(params.get("factory"));
    const item = params.has("item") ? historyUuid(params.get("item")) : null;
    const context = await authenticatedClient();
    const { db } = context;
    await Promise.all(["factory", "orders", "lean"].map(module => authorize(factory, module, "view", context)));

    if (!item) {
      const start = Date.parse(params.get("from") || "");
      const finish = Date.parse(params.get("to") || "");
      if (!Number.isFinite(start) || !Number.isFinite(finish) || finish <= start || finish - start > 32 * day) {
        throw { code: "22023" };
      }
      const from = new Date(start).toISOString();
      const to = new Date(finish).toISOString();
      const orders = () => db.from("production_orders").select(orderColumns).eq("factory_id", factory).order("id");
      const revisions = () => db.from("production_plan_revisions").select("id,item_id")
        .eq("factory_id", factory).order("id");
      const [scheduled, finished, started, finishOnly, oldPlan, newPlan] = await Promise.all([
        readRows((a, b) => orders().lt("start_time", to).gt("expected_finish", from).range(a, b)),
        readRows((a, b) => orders().lt("actual_start", to).gte("actual_finish", from).range(a, b)),
        readRows((a, b) => orders().lt("actual_start", to).is("actual_finish", null).range(a, b)),
        readRows((a, b) => orders().is("actual_start", null).gte("actual_finish", from).lt("actual_finish", to).range(a, b)),
        readRows((a, b) => revisions().lt("before_start", to).gt("before_finish", from).range(a, b)),
        readRows((a, b) => revisions().lt("after_start", to).gt("after_finish", from).range(a, b)),
      ]);
      const found = new Map([...scheduled, ...finished, ...started, ...finishOnly].map(row => [String(row.id), row]));
      const historical = [...new Set([...oldPlan, ...newPlan].map(row => String(row.item_id)))]
        .filter(id => !found.has(id));
      for (let offset = 0; offset < historical.length; offset += 100) {
        const result = await orders().in("id", historical.slice(offset, offset + 100));
        if (result.error) throw result.error;
        for (const row of result.data) found.set(String(row.id), row);
      }
      const rows = [...found.values()].sort((a, b) =>
        String(a.code).localeCompare(String(b.code), undefined, { numeric: true }));
      if (rows.length > 300) throw { code: "F3701" };
      const entries = await timeline(db, factory, rows, from, to);
      return NextResponse.json({ entries, asOf: new Date().toISOString() }, { headers });
    }
    if (params.has("from") || params.has("to")) throw { code: "22023" };
    const orderRead = await db.from("production_orders").select(orderColumns)
      .eq("factory_id", factory).eq("id", item).limit(1);
    if (orderRead.error) throw orderRead.error;
    const order = orderRead.data[0];
    if (!order) throw { code: "P0002" };
    const canView = async (module: string) => {
      const result = await db.rpc("can_access", { factory, module, action: "view" });
      if (result.error) throw result.error;
      return result.data === true;
    };
    const [plan, execution, delay, loans, request, downtimeView, maintenanceView] = await Promise.all([
      readRows((a, b) => db.from("production_plan_revisions").select(revisionColumns)
        .eq("factory_id", factory).eq("item_id", item).order("revision_no").range(a, b)),
      db.rpc("production_execution_context", { factory, item }),
      db.rpc("production_delay_read", { factory, item }),
      readRows((a, b) => db.from("production_transfers")
        .select("id,original_id,alternative_id,downtime_id,created_at,ended_at,created_by,reason")
        .eq("factory_id", factory).eq("order_id", item).order("created_at").order("id").range(a, b)),
      order.request_id ? db.from("production_requests").select("code,required_by")
        .eq("factory_id", factory).eq("id", order.request_id).limit(1) : { data: [], error: null },
      canView("downtime"),
      canView("maintenance"),
    ]);
    if (execution.error) throw execution.error;
    if (delay.error) throw delay.error;
    if (request.error) throw request.error;
    const { history = [], line_transfers = [], return_transfers = [] } = execution.data;
    const linkedIds = [...new Set([...loans.map(row => row.downtime_id),
      ...line_transfers.map((transfer: Row) => transfer.source_downtime)].filter(Boolean))] as string[];
    const stops = new Map<string, Row>();
    if (downtimeView) {
      const findStops = () => db.from("downtime_events")
        .select("id,line_id,work_center_id,started_at,ended_at,stop_nature,planned_activity,approved_cause_id,reason_id,initial_note,engineering_note")
        .eq("factory_id", factory).order("started_at").order("id");
      const related = await readRows((a, b) => findStops().eq("order_id", item).range(a, b));
      for (const stop of related) stops.set(String(stop.id), stop);
      const missing = linkedIds.filter(id => !stops.has(id));
      for (let offset = 0; offset < missing.length; offset += 100) {
        const result = await findStops().in("id", missing.slice(offset, offset + 100));
        if (result.error) throw result.error;
        for (const stop of result.data) stops.set(String(stop.id), stop);
      }
    }
    const sortedStops = [...stops.values()].sort((a, b) =>
      String(b.started_at).localeCompare(String(a.started_at)));
    const visibleStops = sortedStops.slice(0, 20);
    const latestCorrections = new Map<string, Row>();
    if (visibleStops.length) {
      const corrections = await readRows((a, b) => db.from("downtime_classification_corrections")
        .select("event_id,stop_nature,planned_activity,reason_id,note")
        .eq("factory_id", factory).in("event_id", visibleStops.map(stop => String(stop.id)))
        .order("corrected_at", { ascending: false }).order("id", { ascending: false }).range(a, b));
      for (const row of corrections) {
        const id = String(row.event_id);
        if (!latestCorrections.has(id)) latestCorrections.set(id, row);
      }
    }
    const stopDetails = await Promise.all(visibleStops.map(async stop => {
      const record = { ...stop, correction: latestCorrections.get(String(stop.id)) || null };
      if (!maintenanceView) return record;
      const result = await db.rpc("production_loss_maintenance_context", { factory, event: stop.id });
      if (result.error) throw result.error;
      const evidence = result.data?.evidence;
      return { ...record, maintenance: evidence?.operation === "LINK" ? {
        valid: evidence.valid, approved_start: evidence.approved_start, approved_end: evidence.approved_end,
      } : null };
    }));
    return NextResponse.json({ order, plan, history, line_transfers, return_transfers, loans,
      delay: delay.data?.history || [], delayTotal: delay.data?.history_total || 0,
      stops: stopDetails, stopTotal: sortedStops.length, downtimeView, maintenanceView,
      request: request.data[0] || null, asOf: new Date().toISOString() }, { headers });
  } catch (error) {
    if (error && typeof error === "object" && "code" in error && error.code === "F3701") {
      return NextResponse.json({ error: "f37ScopeTooLarge" }, { status: 422, headers });
    }
    return historyError(error);
  }
}
