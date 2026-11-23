// Only event identities come from the caller. The database supplies frozen review evidence.
import { calculateProductionLoss } from "../../../src/utils/production-loss-impact.mjs";

const json = (body, status = 200) => Response.json(body, { status });
const uuid = (value) => typeof value === "string" &&
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
class BackendError extends Error {
  constructor(message, status) {
    super(message);
    this.status = status;
  }
}

export function createLossEstimateHandler({ url, key: publicKey, service: serviceKey, fetch = globalThis.fetch }) {
  async function request(path, key, bearer,
    options = {}) {
    const response = await fetch(`${url}${path}`, {
      ...options,
      headers: {
        apikey: key,
        Authorization: bearer,
        ...(options.body ? { "Content-Type": "application/json" } : {}),
        ...options.headers,
      },
    });
      if (!response.ok) {
        const failure = await response.json().catch(() => ({}));
        const known = ["permission_denied", "loss_estimate_context_mismatch",
          "loss_estimate_locked", "loss_estimate_incomplete", "downtime_not_reviewable"];
        const code = known.includes(failure.message) ? failure.message : `backend_${response.status}`;
        throw new BackendError(code, code === "permission_denied" ? 403
          : ["loss_estimate_context_mismatch", "loss_estimate_locked"].includes(code) ? 409
            : ["loss_estimate_incomplete", "downtime_not_reviewable"].includes(code) ? 422 : response.status);
      }
    return response.json();
  }

  return async (req) => {
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

      const input = await request("/rest/v1/rpc/production_loss_review_inputs", publicKey,
        authorization, { method: "POST", body: JSON.stringify({ factory: body.factory, event: body.event }) });
      const event = input.event;
      if (!event || event.id !== body.event || event.factory_id !== body.factory ||
        !event.ended_at || event.loss_model_version !== 1)
        return json({ error: "downtime_not_reviewable" }, 422);
      const correction = input.correction;
      const effectiveEvent = { ...event,
        stop_nature: correction?.stop_nature || event.stop_nature,
        planned_activity: correction?.planned_activity || event.planned_activity };
      const actual = input.actual;
      const observations = input.observations.flatMap((record) => {
        const row = record.saved;
        const previous = record.event;
        const measured = record.actual;
        const estimate = row.result;
        if (!previous || !measured || !estimate) return [];
        const assumptions = estimate.assumptions;
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
      const estimate = calculateProductionLoss(effectiveEvent, input.samples, actual,
        Date.now(), observations, input.maintenance);
      Object.assign(estimate, { input_hash: input.input_hash });
      if (estimate.readiness !== "READY")
        return json({ error: "loss_estimate_incomplete", missing: estimate.missing }, 422);
      const id = await request("/rest/v1/rpc/persist_production_loss_estimate",
        serviceKey, `Bearer ${serviceKey}`, { method: "POST", body: JSON.stringify({
          factory: body.factory, event: body.event, actor: user.id, estimate,
          correction: correction?.id || null,
        }) });
      return json({ id });
    } catch (error) {
      if (error instanceof BackendError) return json({ error: error.message }, error.status);
      const message = error instanceof Error ? error.message : "error";
      return json({ error: message.startsWith("backend_") ? message : "error" }, 400);
    }
  };
}
