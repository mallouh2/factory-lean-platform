/** Complete, bounded protected-reader collection. Never use a partial page as capacity truth. */
export async function collectMaintenancePages(read, size, limit = 500) {
  const rows = [], ids = new Set();
  let total, first;
  for (let page = 1; page <= Math.ceil(limit / size) + 1; page++) {
    const data = await read(page);
    if (!data || !Array.isArray(data.rows) || !Number.isSafeInteger(data.total) || data.total < 0 || data.total > limit)
      throw Error('maintenancePlanningIncomplete');
    if (!first) { first = data; total = data.total; }
    if (data.total !== total || data.rows.length !== Math.min(size, total - rows.length))
      throw Error('maintenancePlanningIncomplete');
    for (const row of data.rows) {
      if (!row.id || ids.has(row.id)) throw Error('maintenancePlanningIncomplete');
      ids.add(row.id); rows.push(row);
    }
    if (rows.length === total) return { ...first, rows };
  }
  throw Error('maintenancePlanningIncomplete');
}

export const maintenanceQueueViews = ['needs', 'proposed', 'confirmed', 'due', 'progress', 'completed'];
export function maintenanceQueueView(request, schedule, now = Date.now()) {
  if (['COMPLETED', 'VERIFIED', 'CANCELLED'].includes(request.status)) return 'completed';
  if (request.status === 'IN_PROGRESS' || schedule?.actual_hold) return 'progress';
  if (schedule?.state === 'INVALIDATED' || (schedule?.state === 'CONFIRMED' && Date.parse(schedule.planned_start) <= now)) return 'due';
  if (schedule?.state === 'CONFIRMED') return 'confirmed';
  if (schedule?.state === 'PROPOSED') return 'proposed';
  return 'needs';
}

/** Presentation of persisted SQL resource scope; no future alternative or buffer assumptions. */
export function maintenanceOccupancy(schedules, centers = [], transfers = [], routing = [], now = Date.now(), orders = []) {
  return schedules.filter(s => ['CONFIRMED', 'INVALIDATED'].includes(s.state)).map(s => {
    const machines = (s.resources || []).filter(r => r.machine_id).map(r => String(r.machine_id));
    const lines = new Set((s.resources || []).filter(r => r.line_id).map(r => String(r.line_id)));
    for (const m of centers.filter(c => machines.includes(String(c.id)))) if (m.line_id) lines.add(String(m.line_id));
    for (const transfer of transfers.filter(t => !t.ended_at && machines.includes(String(t.alternative_id)))) {
      const owner = orders.find(o => String(o.id)===String(transfer.order_id));
      if (owner?.line_id) lines.add(String(owner.line_id));
    }
    const products = routing.filter(r => r.kind === 'work_center' && machines.includes(String(r.work_center_id))).map(r => String(r.product_id));
    const planned = Date.parse(s.planned_start), end = Date.parse(s.planned_end), hold = Date.parse(s.hold_started_at || '');
    const unknown = !Number.isFinite(planned) || !Number.isFinite(end) || end <= planned;
    return { id: s.id, lineIds: [...lines], machineIds: machines, productIds: products,
      start: unknown ? -Infinity : Math.min(planned, Number.isFinite(hold) ? hold : planned),
      finish: unknown || s.actual_hold || s.state === 'INVALIDATED' || end <= now ? Infinity : end };
  });
}

/** One occupancy interval per reservation, even when machine and line both match.
 * @param {unknown} product */
export function maintenanceSlots(reservations, line, product = null) {
  return reservations.filter(r => r.lineIds.includes(String(line.id)) || (product && r.productIds.includes(String(product))))
    .map(r => ({ order: { id: `maintenance:${r.id}` }, maintenance: true, start: r.start, finish: r.finish }));
}

export function maintenanceVisualWindow(schedule, now = Date.now()) {
  const start = Date.parse(schedule.planned_start), plannedEnd = Date.parse(schedule.planned_end);
  const hold = Date.parse(schedule.hold_started_at || '');
  const physical=(schedule.actual_stops || []).map(stop=>({start:Date.parse(stop.started_at),finish:stop.ended_at?Date.parse(stop.ended_at):now}));
  return { start: Math.min(start, Number.isFinite(hold) ? hold : start,...physical.map(stop=>stop.start)), plannedEnd,
    finish: Math.max(plannedEnd, schedule.released_at ? Date.parse(schedule.released_at) : schedule.actual_hold ? now : plannedEnd,...physical.map(stop=>stop.finish)),
    continuing: schedule.actual_hold || schedule.state === 'INVALIDATED' || schedule.missed_window };
}
