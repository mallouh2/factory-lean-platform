import { comparableExposure, operatingRuntime, metricChange, scrapRate, runtimeByShift } from './lean-analysis.mjs';
const time = v => Date.parse(v);
const known = v => v !== null && v !== undefined && Number.isFinite(Number(v));
export function measuredHours(intervals, subject, products, from, to) {
  return intervals.filter(x => x.subject_id === subject && products.includes(x.product_id)).reduce((sum, x) =>
    sum + Math.max(0, Math.min(time(x.ended_at), time(to)) - Math.max(time(x.started_at), time(from))) / 3600000, 0);
}
export function typedTotals(rows, field) {
  const result = {};
  for (const row of rows) {
    const unit = row.output_unit || row.unit;
    if (unit && known(row[field])) result[unit] = (result[unit] || 0) + Number(row[field]);
  }
  return result;
}
/** Whole wall-clock window includes stoppages between measured runtime segments. */
export function windowMetrics(occurrences, entries, from, to, hours, { product_id, subject_id, mechanism, include_end = false }) {
  const within = value => time(value) >= time(from) && (include_end ? time(value) <= time(to) : time(value) < time(to));
  const inWindow=occurrences.filter(x=>within(x.occurred_at));
  const events = inWindow.filter(x => x.product_id === product_id);
  const unallocated=inWindow.some(x=>!x.product_id&&x.loss_details?.assumptions?.some(segment=>segment.product_id===product_id));
  const produced = entries.filter(x => x.product_id === product_id && (mechanism === 'scrap' ? x.line_id === subject_id : x.work_center_id === subject_id || x.machine_ids?.includes(subject_id)) && within(x.created_at));
  const sum = (rows, field) => rows.length && rows.every(x => known(x[field])) ? rows.reduce((n, x) => n + Number(x[field]), 0) : rows.length ? null : 0;
  const loss = unallocated?null:sum(events, 'loss_minutes'), scrap = unallocated?null:sum(events, 'scrap_kg'), weight = sum(produced, 'produced_weight_kg');
  const frequency = new Set(events.map(x => x.event_id)).size;
  const shifts = [...new Set([...events, ...produced].map(x => x.shift_id || null))].map(shift_id => {
    const e = events.filter(x => (x.shift_id || null) === shift_id), p = produced.filter(x => (x.shift_id || null) === shift_id);
    const scrap_kg = sum(e, 'scrap_kg'), produced_kg = sum(p, 'produced_weight_kg');
    return { shift_id, frequency: new Set(e.map(x => x.event_id)).size, loss_minutes: sum(e, 'loss_minutes'), scrap_kg,
      scrap_rate: scrap_kg === null ? null : scrapRate(scrap_kg, produced_kg), lost_output: typedTotals(e, 'lost_output'),
      response_minutes: e.map(x => ({ event_id: x.event_id, minutes: Math.max(0, time(x.ended_at) - time(x.occurred_at)) / 60000 })), occurrences: e };
  });
  return { runtime_hours: hours, frequency:unallocated?null:frequency, occurrences_per_hour: hours > 0&&!unallocated ? frequency / hours : null,
    loss_minutes: loss, loss_minutes_per_hour: hours > 0 && loss !== null ? loss / hours : null, scrap_kg: scrap,
    produced_kg: weight, scrap_rate: scrap === null ? null : scrapRate(scrap, weight), lost_output: typedTotals(events, 'lost_output'),
    wip: typedTotals(produced.map(x => ({ ...x, output_unit: x.unit })), 'effective_unfinished'), shifts,
    unknown_loss: events.filter(x => !known(x.loss_minutes)).length, unknown_scrap: events.filter(x => !known(x.scrap_kg)).length,
    unknown_weight: produced.filter(x => !known(x.produced_weight_kg)).length,product_attribution_missing:unallocated };
}
export function baselineEvidence({ checkpoints, occurrences, entries, problem, initiative, as_of, source_complete = true }) {
  const subject_id = problem.machine_id || problem.line_id, product_id = initiative.product_id;
  const from = initiative.baseline_from, to = initiative.baseline_to;
  const coverage = source_complete && checkpoints.length > 0 && time(checkpoints[0].captured_at) <= time(from);
  const intervals = runtimeByShift(operatingRuntime(checkpoints, as_of),checkpoints);
  const hours = coverage ? measuredHours(intervals, subject_id, [product_id], from, to) : null;
  return { version: 1, problem_id: problem.id, product_id, subject_id, from, to, runtime_hours: hours,
    coverage_complete: coverage, as_of, metrics: windowMetrics(occurrences, entries, from, to, hours, { product_id, subject_id, mechanism: problem.mechanism, include_end: true }),
    note: 'Produced weight uses immutable recording-time weight snapshots and declaration timestamps. Missing history is unknown.' };
}
export function compareEvidence({ checkpoints, occurrences, entries, problem, product_id, cutoff, desired_hours, baseline = null, as_of, source_complete = true }) {
  const subject_id = problem.machine_id || problem.line_id;
  if (problem.product_id && problem.product_id !== product_id || baseline && (baseline.product_id !== product_id || baseline.problem_id !== problem.id)) throw new Error('lean_comparison_product');
  const intervals = runtimeByShift(operatingRuntime(checkpoints, as_of),checkpoints);
  if (baseline && !(baseline.runtime_hours > 0)) {
    return { version:1, problem_id:problem.id, product_id, subject_id, cutoff, as_of, complete:false,
      before:{desired_hours:null,collected_hours:baseline.runtime_hours,remaining_hours:null,complete:false},
      after:{desired_hours:null,collected_hours:measuredHours(intervals,subject_id,[product_id],cutoff,as_of),remaining_hours:null,complete:false},
      before_metrics:baseline.metrics,after_metrics:null,changes:{},threshold_percent:problem.threshold_percent??10,source_complete,
      note:'Baseline runtime is unknown or zero. No comparable target can be inferred.' };
  }
  const before = baseline ? { desired_hours: Number(baseline.runtime_hours || desired_hours), collected_hours: baseline.runtime_hours || 0,
    remaining_hours: baseline.runtime_hours ? 0 : Number(desired_hours), complete: Boolean(baseline.coverage_complete && baseline.runtime_hours > 0), intervals: [{ started_at: baseline.from, ended_at: baseline.to }] }
    : comparableExposure(intervals, { subject_id, product_id, cutoff, desired_hours, direction: 'before' });
  const after = comparableExposure(intervals, { subject_id, product_id, cutoff, desired_hours: before.desired_hours, direction: 'after' });
  const metrics = exposure => exposure.intervals.length ? windowMetrics(occurrences, entries, exposure.intervals[0].started_at,
    exposure.intervals.at(-1).ended_at, exposure.collected_hours, { product_id, subject_id, mechanism: problem.mechanism }) : null;
  const before_metrics = baseline?.metrics || metrics(before), after_metrics = metrics(after);
  const complete = source_complete && before.complete && after.complete;
  const changes = Object.fromEntries(['occurrences_per_hour', 'loss_minutes', 'loss_minutes_per_hour', 'scrap_kg', 'scrap_rate'].map(key =>
    [key, complete ? metricChange(before_metrics?.[key], after_metrics?.[key], problem.threshold_percent ?? 10) : { percent: null, suggestion: 'INSUFFICIENT_DATA' }]));
  for (const key of ['lost_output','wip']) changes[key] = Object.fromEntries([...new Set([...Object.keys(before_metrics?.[key] || {}), ...Object.keys(after_metrics?.[key] || {})])].map(unit =>
    [unit, complete ? metricChange(before_metrics?.[key]?.[unit],after_metrics?.[key]?.[unit],problem.threshold_percent ?? 10) : { percent:null,suggestion:'INSUFFICIENT_DATA' }]));
  return { version: 1, problem_id: problem.id, product_id, subject_id, cutoff, as_of, complete, before, after, before_metrics, after_metrics, changes,
    threshold_percent: problem.threshold_percent ?? 10, source_complete, note: 'Separate metric suggestions; human verification is required. No combined score.' };
}
