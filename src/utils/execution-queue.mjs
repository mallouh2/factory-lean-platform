/** The queue reads the persisted plan; it never computes or changes a schedule. */
export function lineExecutionQueue(items, lineId) {
  const lineItems = items.filter((item) => String(item.line_id || "") === String(lineId));
  const active = lineItems.find((item) => item.status === "active");
  const planned = lineItems.filter((item) => item.status === "planned" && !item.actual_start
    && item.start_time && item.expected_finish
    && Date.parse(String(item.expected_finish)) > Date.parse(String(item.start_time)))
    .sort((a, b) => Date.parse(String(a.start_time)) - Date.parse(String(b.start_time))
      || String(a.id).localeCompare(String(b.id)));
  return {
    current: active || planned[0] || null,
    next: active ? planned[0] || null : planned[1] || null,
    readyId: active ? null : planned[0]?.id || null,
  };
}

export function executionTiming(item, now = Date.now()) {
  const plannedStart = Date.parse(String(item.start_time || ""));
  const plannedFinish = Date.parse(String(item.expected_finish || ""));
  const actualStart = Date.parse(String(item.actual_start || ""));
  const actualFinish = Date.parse(String(item.actual_finish || ""));
  return {
    startVarianceMinutes: Number.isFinite(actualStart) && Number.isFinite(plannedStart)
      ? Math.round((actualStart - plannedStart) / 60000) : null,
    finishVarianceMinutes: Number.isFinite(actualFinish) && Number.isFinite(plannedFinish)
      ? Math.round((actualFinish - plannedFinish) / 60000) : null,
    startOverdueMinutes: !Number.isFinite(actualStart) && Number.isFinite(plannedStart)
      && now > plannedStart ? Math.floor((now - plannedStart) / 60000) : null,
    overdueMinutes: !Number.isFinite(actualFinish) && Number.isFinite(plannedFinish)
      && now > plannedFinish ? Math.floor((now - plannedFinish) / 60000) : null,
  };
}
