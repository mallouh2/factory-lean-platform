import { calculateProductionLoss, suggestScrapCalibration } from "./production-loss-impact.mjs";

const number = value => value === null || value === undefined || value === "" ? null : Number(value);
const effective = record => ({ ...record.event,
  stop_nature: record.correction?.stop_nature || record.event.stop_nature,
  planned_activity: record.correction?.planned_activity || record.event.planned_activity });

/** Same review calculations and observation mapping, with event-scoped server reads.
 * @param {Record<string, any>} selected
 * @param {Array<Record<string, any>>} candidates
 * @param {(event: string) => Promise<Array<any>>} contexts
 */
export async function deliverLossReview(selected, candidates, contexts, now = Date.now()) {
  const observations = [];
  for (const item of candidates) {
    if (item.event.id === selected.event.id || !item.actual) continue;
    const event = effective(item);
    const estimate = item.saved?.result && typeof item.saved.result === "object"
      ? item.saved.result : calculateProductionLoss(event, await contexts(event.id), item.actual, now);
    observations.push({ work_center_id: event.work_center_id, recorded_at: item.actual.recorded_at,
      stop_nature: event.stop_nature, planned_activity: event.planned_activity,
      product_id: estimate.assumptions[0]?.product_id, readiness: estimate.readiness,
      scrap_unit: item.actual.scrap_unit, estimated_total_scrap: estimate.estimated_total_scrap,
      actual_scrap_quantity: number(item.actual.scrap_quantity),
      actual_shutdown_scrap: number(item.actual.shutdown_scrap_quantity),
      actual_restart_scrap: number(item.actual.restart_scrap_quantity) });
  }
  const event = effective(selected);
  const calculation = calculateProductionLoss(event, await contexts(event.id), selected.actual, now, observations);
  const estimate = selected.saved?.result && typeof selected.saved.result === "object"
    ? selected.saved.result : calculation;
  return { ...selected, calculation, suggestions: ["shutdown", "restart"].map(parameter =>
    suggestScrapCalibration(event, estimate, observations, parameter)).filter(Boolean) };
}

/** Consume every server page without exposing raw context history to the client. */
export async function collectHistoryPages(readPage) {
  const first = await readPage(1);
  const rows = [...first.rows];
  for (let page = 2; page <= first.pages; page++) {
    const next = await readPage(page);
    if (next.total !== first.total || next.pages !== first.pages)
      throw new Error("history_changed_during_read");
    rows.push(...next.rows);
  }
  if (rows.length !== first.total) throw new Error("history_changed_during_read");
  return rows;
}
