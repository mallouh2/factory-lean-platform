/** Presentation only: timestamps remain the source of truth. */
export function formatDuration(minutes, locale = "en") {
  const total = Math.max(0, Math.floor(Number(minutes) || 0));
  const hours = Math.floor(total / 60),
    rest = total % 60;
  const unit = (value, name) =>
    new Intl.NumberFormat(locale, {
      style: "unit",
      unit: name,
      unitDisplay: "long",
    }).format(value);
  return [
    hours ? unit(hours, "hour") : "",
    rest || !hours ? unit(rest, "minute") : "",
  ]
    .filter(Boolean)
    .join(locale === "ar" ? " و" : " ");
}
/** A sequence describes downstream dependency, never a replacement for the machine's actual state. */
export function evaluateFlow(centers, stops, transfers, now = Date.now()) {
  /** @type {Record<string,{state:string,source:string|null}>} */
  const result = {};
  const active = centers.filter((c) => !c.archived);
  for (const c of active) result[c.id] = { state: "clear", source: null };
  const stopped = active.filter(
    (c) =>
      ["stopped", "setup", "offline"].includes(c.status) &&
      ["blocking", "buffer"].includes(c.dependency_mode) &&
      c.impact_scope !== "none",
  );
  const unresolved = new Set();
  const candidates = [];
  for (const c of stopped) {
    const stop = stops.find((d) => d.work_center_id === c.id && !d.ended_at);
    const buffered =
      c.dependency_mode === "buffer" &&
      stop &&
      now < Date.parse(stop.started_at) + Number(c.buffer_minutes) * 60000;
    const transfer = transfers.find(
      (x) => x.original_id === c.id && !x.ended_at,
    );
    const alternative =
      transfer && active.find((x) => x.id === transfer.alternative_id);
    if (buffered) result[c.id] = { state: "bufferActive", source: c.id };
    else if (alternative?.status === "running") {
      result[c.id] = { state: "transferred", source: c.id };
      candidates.push({ original: c, alternative });
    } else unresolved.add(c.id);
  }
  const propagate = () => {
    for (const c of stopped.filter((x) => unresolved.has(x.id))) {
      result[c.id] = { state: "blocked", source: c.id };
      if (!c.line_id) continue;
      for (const peer of active.filter((x) => x.line_id === c.line_id)) {
        const downstream =
          Number(peer.position) > Number(c.position) &&
          peer.dependency_mode !== "independent";
        if (c.impact_scope === "whole_line" || downstream)
          result[peer.id] = { state: "blocked", source: c.id };
      }
    }
  };
  // A running alternative cannot relieve a bottleneck if its own production flow is blocked.
  for (let pass = 0; pass <= candidates.length; pass++) {
    propagate();
    let changed = false;
    for (const candidate of candidates)
      if (
        result[candidate.alternative.id].state === "blocked" &&
        !unresolved.has(candidate.original.id)
      ) {
        unresolved.add(candidate.original.id);
        changed = true;
      }
    if (!changed) break;
  }
  return result;
}
/** Configurable, dimensionless priority proxy; estimates are not measured lost output. */
export function rankDowntime(
  events,
  from,
  to,
  settings = {},
  now = Date.now(),
  transfers = [],
) {
  const groups = new Map();
  for (const event of events) {
    const start = Math.max(Date.parse(event.started_at), Date.parse(from));
    const end = Math.min(
      event.ended_at ? Date.parse(event.ended_at) : now,
      Date.parse(to),
      now,
    );
    const minutes = Math.max(0, (end - start) / 60000);
    if (!minutes) continue;
    const blocking = event.blocking_at_start === true;
    let blockedMinutes = blocking
      ? Math.max(
          0,
          (end -
            Math.max(
              start,
              Date.parse(event.started_at) +
                Number(event.buffer_minutes_at_start || 0) * 60000,
            )) /
            60000,
        )
      : 0;
    // Transfer history records the interval during which the original stop was mitigated.
    for (const transfer of transfers.filter(
      (x) => x.downtime_id === event.id,
    )) {
      const mitigationStart = Math.max(
        start,
        Date.parse(transfer.created_at),
        Date.parse(event.started_at) +
          Number(event.buffer_minutes_at_start || 0) * 60000,
      );
      const mitigationEnd = Math.min(
        end,
        transfer.ended_at ? Date.parse(transfer.ended_at) : now,
      );
      blockedMinutes = Math.max(
        0,
        blockedMinutes - Math.max(0, mitigationEnd - mitigationStart) / 60000,
      );
    }
    const lostUnits =
      event.rate_at_start > 0
        ? (blockedMinutes * Number(event.rate_at_start)) / 60
        : null;
    const weight = Number(settings.impact_blocking_weight ?? 2);
    const frequency = Number(settings.impact_frequency_minutes ?? 5);
    // Equivalent production minutes make unlike product units comparable.
    const score =
      minutes +
      blockedMinutes * (weight - 1) +
      frequency +
      (lostUnits === null ? 0 : blockedMinutes);
    const group = groups.get(event.reason_id) || {
      reason_id: event.reason_id,
      minutes: 0,
      score: 0,
      events: [],
      lostUnits: 0,
      hasEstimate: false,
    };
    group.minutes += minutes;
    group.score += score;
    group.events.push({ ...event, minutes, score, lostUnits });
    if (lostUnits !== null) {
      group.hasEstimate = true;
      group.lostUnits += lostUnits;
    }
    groups.set(event.reason_id, group);
  }
  return [...groups.values()].sort((a, b) => b.score - a.score);
}
