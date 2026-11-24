import { ganttLayout } from "./planning-gantt.mjs";

const stamp = value => typeof value === "string" ? Date.parse(value) : NaN;

/** @typedef {import("../types").Row} Row */
/** @typedef {{id: string, kind: string, line: string, start: string, finish: string,
 * open?: boolean, run?: Row}} Segment */

/** @returns {Segment | null} */
function planInterval(revision, kind) {
  if (!revision?.after_line_id || !(stamp(revision.after_finish) > stamp(revision.after_start))) return null;
  return { id: kind + "-" + revision.revision_no, kind, line: revision.after_line_id,
    start: revision.after_start, finish: revision.after_finish };
}

/** Interpret source records without deriving execution intervals from order bounds.
 * @param {Row} order
 * @param {Row[]} revisions
 * @param {Row[]} history
 * @param {number} revisionNo
 * @param {string} asOf
 */
export function planActualEvidence(order, revisions, history, revisionNo, asOf) {
  const ordered = [...revisions].sort((a, b) => Number(a.revision_no) - Number(b.revision_no));
  const first = ordered[0];
  const original = first?.event === "initial" && Number(first.revision_no) === 1
    ? planInterval(first, "original") : null;
  const revision = ordered.find(row => Number(row.revision_no) === revisionNo) || ordered.at(-1) || null;
  const selected = planInterval(revision, revision?.event === "baseline" ? "baseline" : "approved");
  const approved = selected?.kind === "approved" ? selected : null;
  /** @type {Segment[]} */
  const runs = history.flatMap(run => {
    if (!["ACTIVE", "INTERRUPTED", "FINISHED"].includes(String(run.state)) || !run.line_id) return [];
    const open = run.state === "ACTIVE" && !run.ended_at;
    const finish = open ? asOf : run.ended_at;
    if (!(stamp(finish) > stamp(run.started_at))) return [];
    return [{ id: String(run.id), kind: "actual", line: String(run.line_id),
      start: String(run.started_at), finish: String(finish), open, run }];
  }).sort((a, b) => stamp(a.start) - stamp(b.start) || a.id.localeCompare(b.id));
  // A legacy order's bounds are useful evidence, but not a line placement or continuous run.
  const bounds = [
    { id: "actual-start", kind: "start", start: order.actual_start },
    { id: "actual-finish", kind: "finish", start: order.actual_finish },
  ].filter(point => Number.isFinite(stamp(point.start)));
  const completeAnchor = (kind, date) => runs.some(run => (kind === "start" || !run.open) &&
    stamp(kind === "start" ? run.start : run.finish) === stamp(date));
  const unmatchedBounds = bounds.filter(point => !completeAnchor(point.kind, point.start));
  const planMatchesCurrent = selected && selected.line === order.line_id &&
    stamp(selected.start) === stamp(order.start_time) && stamp(selected.finish) === stamp(order.expected_finish);
  const delta = (actual, planned) => Number.isFinite(stamp(actual) - stamp(planned))
    ? stamp(actual) - stamp(planned) : null;
  const elapsed = delta(order.actual_finish, order.actual_start);
  return {
    original, selected, revision, ordered, runs, bounds, unmatchedBounds,
    planMatchesCurrent: Boolean(planMatchesCurrent),
    segments: [...(original ? [original] : []),
      ...(selected && (!original || revision?.revision_no !== first.revision_no) ? [selected] : []),
      ...runs],
    startDelta: delta(order.actual_start, approved?.start),
    finishDelta: delta(order.actual_finish, approved?.finish),
    elapsedDelta: elapsed !== null && elapsed >= 0 && approved
      ? elapsed - (stamp(approved.finish) - stamp(approved.start)) : null,
  };
}

export function planActualLayout(segments, from, to, width) {
  return ganttLayout(segments.map(segment => ({ segment, order: {
    id: segment.id, start_time: segment.start, expected_finish: segment.finish,
  } })), stamp(from), stamp(to), width);
}

export function timestampInWindow(value, from, to) {
  const point = stamp(value);
  return point >= stamp(from) && point < stamp(to);
}

/** A missing original approval or a baseline never supplies a planned bar. */
export function planActualTracks(entry, mode, asOf) {
  const evidence = planActualEvidence(entry.order, entry.plan, entry.history, mode === "original" ? 1 : 0, asOf);
  const plan = mode === "original" ? evidence.original
    : evidence.selected?.kind === "approved" ? evidence.selected : null;
  return { ...evidence, chartPlan: plan, segments: [...(plan ? [plan] : []), ...evidence.runs] };
}

/** Fit one order's evidence inside the requested period without changing any timestamps. */
export function fitPlanActualScale(segments, points, from, to) {
  const lo = stamp(from), hi = stamp(to);
  const edges = segments.flatMap(segment => [Math.max(lo, stamp(segment.start)), Math.min(hi, stamp(segment.finish))]);
  for (const point of points) edges.push(stamp(point.start));
  if (!edges.length) return { from, to };
  const first = Math.min(...edges), last = Math.max(...edges);
  const padding = Math.max(15 * 60_000, (last - first) * .05);
  return { from: new Date(Math.max(lo, first - padding)).toISOString(),
    to: new Date(Math.min(hi, last + padding)).toISOString() };
}
