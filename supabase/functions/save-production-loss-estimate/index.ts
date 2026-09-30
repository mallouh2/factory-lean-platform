// Trusted V1 calculation. The browser supplies identities only; every input
// and the calculation itself comes from the database and shared flow model.
import { calculateProductionLoss } from "../../../src/utils/production-loss-impact.mjs";

declare const Deno: {
  env: { get(name: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

const url = Deno.env.get("SUPABASE_URL");
const publicKey = Deno.env.get("SUPABASE_ANON_KEY");
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const json = (body: unknown, status = 200) => Response.json(body, { status });
const uuid = (value: unknown) => typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);

async function request(path: string, key: string, bearer: string,
  options: RequestInit = {}) {
  const response = await fetch(`${url}${path}`, {
    ...options,
    headers: {
      apikey: key,
      Authorization: bearer,
      ...(options.body ? { "Content-Type": "application/json" } : {}),
      ...options.headers,
    },
  });
  if (!response.ok) throw new Error(`backend_${response.status}`);
  return response.json();
}

async function rows(table: string, filters: Record<string, string> = {},
  extra = "") {
  const result: Record<string, unknown>[] = [];
  for (let offset = 0; ; offset += 1000) {
    const query = new URLSearchParams({ select: "*", limit: "1000",
      offset: String(offset) });
    for (const [key, value] of Object.entries(filters))
      query.set(key, `eq.${value}`);
    const page = await request(`/rest/v1/${table}?${query}&${extra}`,
      serviceKey!, `Bearer ${serviceKey}`) as Record<string, unknown>[];
    result.push(...page);
    if (page.length < 1000) return result;
  }
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!url || !publicKey || !serviceKey) return json({ error: "configuration_missing" }, 503);
  try {
    const body = await req.json();
    if (!body || typeof body !== "object" ||
      Object.keys(body).sort().join(",") !== "event,factory" ||
      !uuid(body.factory) || !uuid(body.event))
      return json({ error: "invalid_input" }, 400);
    const authorization = req.headers.get("Authorization") || "";
    if (!/^Bearer\s+\S+$/.test(authorization))
      return json({ error: "unauthorized" }, 401);
    const user = await request("/auth/v1/user", publicKey, authorization);
    if (!uuid(user.id) || !user.email_confirmed_at)
      return json({ error: "unauthorized" }, 401);
    const allowed = await request("/rest/v1/rpc/can_access", publicKey,
      authorization, { method: "POST", body: JSON.stringify({
        factory: body.factory, module: "downtime", action: "edit",
      }) });
    if (allowed !== true) return json({ error: "permission_denied" }, 403);

    const events = await rows("downtime_events", {
      factory_id: body.factory, id: body.event,
    });
    const event = events[0];
    if (!event || !event.ended_at || event.loss_model_version !== 1)
      return json({ error: "downtime_not_reviewable" }, 422);
    const [samples, corrections, actuals, saved, allEvents] = await Promise.all([
      rows("production_loss_context_snapshots", {
        factory_id: body.factory, event_id: body.event,
      }, "order=captured_at.asc,id.asc"),
      rows("downtime_classification_corrections", {
        factory_id: body.factory, event_id: body.event,
      }, "order=corrected_at.desc,id.desc"),
      rows("production_loss_actuals", { factory_id: body.factory }),
      rows("production_loss_estimates", { factory_id: body.factory }),
      rows("downtime_events", { factory_id: body.factory }),
    ]);
    if (saved.some((row) => row.event_id === body.event))
      return json({ error: "loss_estimate_locked" }, 409);
    const correction = corrections[0];
    const effectiveEvent = { ...event,
      stop_nature: correction?.stop_nature || event.stop_nature,
      planned_activity: correction?.planned_activity || event.planned_activity };
    const actual = actuals.find((row) => row.event_id === body.event) || null;
    const eventById = new Map(allEvents.map((row) => [row.id, row]));
    const actualById = new Map(actuals.map((row) => [row.event_id, row]));
    const observations = saved.flatMap((row) => {
      const previous = eventById.get(row.event_id);
      const measured = actualById.get(row.event_id);
      const estimate = row.result as Record<string, unknown> | undefined;
      if (!previous || !measured || !estimate) return [];
      const assumptions = estimate.assumptions as Record<string, unknown>[] | undefined;
      return [{
        work_center_id: previous.work_center_id,
        product_id: assumptions?.[0]?.product_id,
        readiness: estimate.readiness,
        recorded_at: measured.recorded_at,
        stop_nature: estimate.stop_nature,
        planned_activity: estimate.planned_activity,
        scrap_unit: measured.scrap_unit,
        actual_scrap_quantity: measured.scrap_quantity,
        actual_shutdown_scrap: measured.shutdown_scrap_quantity,
        actual_restart_scrap: measured.restart_scrap_quantity,
        estimated_total_scrap: estimate.estimated_total_scrap,
      }];
    });
    const estimate = calculateProductionLoss(effectiveEvent, samples as unknown as
      { id: number; event_id: string; captured_at: string;
        context: Record<string, unknown> }[], actual,
      Date.now(), observations);
    if (estimate.readiness !== "READY")
      return json({ error: "loss_estimate_incomplete", missing: estimate.missing }, 422);
    const id = await request("/rest/v1/rpc/persist_production_loss_estimate",
      serviceKey, `Bearer ${serviceKey}`, { method: "POST", body: JSON.stringify({
        factory: body.factory, event: body.event, actor: user.id, estimate,
        correction: correction?.id || null,
      }) });
    return json({ id });
  } catch (error) {
    const message = error instanceof Error ? error.message : "error";
    return json({ error: message.startsWith("backend_") ? message : "error" }, 400);
  }
});
