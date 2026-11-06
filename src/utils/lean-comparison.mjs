import { comparableExposure, operatingRuntime, metricChange, scrapRate, runtimeByShift } from './lean-analysis.mjs';
import {productionScope,exactQuantitySum} from './production-periods.mjs';
const time = v => Date.parse(v);
const known = v => v !== null && v !== undefined && Number.isFinite(Number(v));
export function measuredHours(intervals, subject, products, from, to) {
  return intervals.filter(x => x.subject_id === subject && products.includes(x.product_id)).reduce((sum, x) =>
    sum + Math.max(0, Math.min(time(x.ended_at), time(to)) - Math.max(time(x.started_at), time(from))) / 3600000, 0);
}
export function typedTotals(rows, field) {
  if(rows.some(x=>Number(x.evidence_version)===2))return Object.fromEntries([...new Set(rows.map(x=>x.output_unit||x.unit).filter(Boolean))].map(unit=>
    [unit,exactQuantitySum(rows.filter(x=>(x.output_unit||x.unit)===unit),field)]));
  const result = {};
  for (const row of rows) {
    const unit = row.output_unit || row.unit;
    if (unit && known(row[field])) result[unit] = (result[unit] || 0) + Number(row[field]);
  }
  return result;
}
/** Whole wall-clock window includes stoppages between measured runtime segments.
 * @param {any[]} occurrences
 * @param {any[]} entries
 * @param {string} from
 * @param {string} to
 * @param {number|null} hours
 * @param {{product_id?:string,product_ids?:string[],subject_id:string,mechanism:string,include_end?:boolean,evidence_version?:number|string}} options
 */
export function windowMetrics(occurrences, entries, from, to, hours, { product_id, product_ids=undefined, subject_id, mechanism, include_end = false, evidence_version=undefined }) {
  const modern=Number(evidence_version)===2||[...occurrences,...entries].some(x=>Number(x.evidence_version)===2);
  const scope=x=>productionScope(x,from,to,{include_end});
  const entryScope=x=>productionScope(x,from,to,{entry:true,include_end});
  const inWindow=occurrences.filter(x=>scope(x)!=='OUTSIDE');
  const products=product_ids??[product_id];
  const events = inWindow.filter(x => products.includes(x.product_id)||product_ids&&x.product_id==null);
  const unallocated=!product_ids&&inWindow.some(x=>!x.product_id&&x.loss_details?.assumptions?.some(segment=>segment.product_id===product_id));
  const produced = entries.filter(x => products.includes(x.product_id) && (mechanism === 'scrap' ? x.line_id === subject_id : x.work_center_id === subject_id || x.machine_ids?.includes(subject_id)) && entryScope(x)!=='OUTSIDE');
  const eventUnknown=events.some(x=>scope(x)!=='CONTAINED'||x.review_current===false);
  const entryUnknown=produced.some(x=>entryScope(x)!=='CONTAINED');
  const reviewUnknown=modern&&produced.some(x=>Number(x.effective_scrap_kg)>0&&x.review_current===false);
  const massUnknown=modern&&(produced.some(x=>!known(x.produced_weight_kg)||!['meter','piece','kg'].includes(x.unit))||events.length>0&&produced.length===0);
  const sum = (rows, field) => modern?exactQuantitySum(rows,field):rows.length && rows.every(x => known(x[field])) ? rows.reduce((n, x) => n + Number(x[field]), 0) : rows.length ? null : 0;
  const loss = unallocated?null:sum(events, 'loss_minutes'), scrap = unallocated||eventUnknown||reviewUnknown?null:sum(events, 'scrap_kg'), weight = entryUnknown?null:sum(produced, 'produced_weight_kg');
  const frequency = eventUnknown?null:new Set(events.map(x => x.event_id)).size;
  const shifts = [...new Set([...events, ...produced].map(x => x.shift_id || null))].map(shift_id => {
    const e = events.filter(x => (x.shift_id || null) === shift_id), p = produced.filter(x => (x.shift_id || null) === shift_id);
    const unknown=e.some(x=>scope(x)!=='CONTAINED'||x.review_current===false)||modern&&p.some(x=>Number(x.effective_scrap_kg)>0&&x.review_current===false);
    const scrap_kg = unknown?null:sum(e, 'scrap_kg'), produced_kg = p.some(x=>entryScope(x)!=='CONTAINED')?null:sum(p, 'produced_weight_kg');
    return { shift_id, frequency: unknown?null:new Set(e.map(x => x.event_id)).size, loss_minutes: sum(e, 'loss_minutes'), scrap_kg,
      scrap_rate: scrap_kg === null ? null : scrapRate(scrap_kg, produced_kg), lost_output: typedTotals(e, 'lost_output'),
      response_minutes: e.map(x => ({ event_id: x.event_id, minutes: x.time_precision==='SHIFT_PERIOD'||!x.occurred_at?null:Math.max(0, time(x.ended_at) - time(x.occurred_at)) / 60000 })), occurrences: e };
  });
  return { ...(modern?{evidence_version:2,time_basis:'production',status:eventUnknown||entryUnknown||reviewUnknown||massUnknown||unallocated||events.some(x=>!known(x.scrap_kg))?'INCOMPLETE':events.length||produced.length?'READY':'NA',
      unknown_attribution_records:events.filter(x=>scope(x)!=='CONTAINED').length+produced.filter(x=>entryScope(x)!=='CONTAINED').length,
      unreviewed_records:produced.filter(x=>Number(x.effective_scrap_kg)>0&&x.review_current===false).length}:{}),
    runtime_hours: hours, frequency:unallocated?null:frequency, occurrences_per_hour: hours > 0&&!unallocated&&frequency!==null ? frequency / hours : null,
    loss_minutes: loss, loss_minutes_per_hour: hours > 0 && loss !== null ? loss / hours : null, scrap_kg: scrap,
    produced_kg: weight, scrap_rate: scrap === null ? null : scrapRate(scrap, weight), lost_output: typedTotals(events, 'lost_output'),
    wip: typedTotals(produced.map(x => ({ ...x, output_unit: x.unit,effective_unfinished:entryScope(x)==='CONTAINED'?x.effective_unfinished:null })), 'effective_unfinished'), shifts,
    unknown_loss: events.filter(x => !known(x.loss_minutes)).length, unknown_scrap: events.filter(x => !known(x.scrap_kg)||scope(x)!=='CONTAINED'||x.review_current===false).length,
    unknown_weight: produced.filter(x => !known(x.produced_weight_kg)||entryScope(x)!=='CONTAINED').length,product_attribution_missing:unallocated };
}
export function baselineEvidence({ checkpoints, occurrences, entries, problem, initiative, as_of, source_complete = true, evidence_version=undefined }) {
  const subject_id = problem.machine_id || problem.line_id, product_id = initiative.product_id;
  const from = initiative.baseline_from, to = initiative.baseline_to;
  const coverage = source_complete && checkpoints.length > 0 && time(checkpoints[0].captured_at) <= time(from);
  const intervals = runtimeByShift(operatingRuntime(checkpoints, as_of),checkpoints);
  const hours = coverage ? measuredHours(intervals, subject_id, [product_id], from, to) : null;
  const metrics=windowMetrics(occurrences, entries, from, to, hours, { product_id, subject_id, mechanism: problem.mechanism, include_end: true,evidence_version });
  return { version:metrics.evidence_version??1, ...(metrics.evidence_version===2?{time_basis:'production',status:!coverage||metrics.status==='INCOMPLETE'?'INCOMPLETE':metrics.status}:{}),problem_id: problem.id, product_id, subject_id, from, to, runtime_hours: hours,
    coverage_complete: coverage, as_of, metrics,
    note:metrics.evidence_version===2?'Whole supported production periods only; unknown attribution and pending evidence are not zero.':'Produced weight uses immutable recording-time weight snapshots and declaration timestamps. Missing history is unknown.' };
}
export function compareEvidence({ checkpoints, occurrences, entries, problem, product_id, cutoff, desired_hours, baseline = null, as_of, source_complete = true, evidence_version=undefined }) {
  const subject_id = problem.machine_id || problem.line_id;
  if (problem.product_id && problem.product_id !== product_id || baseline && (baseline.product_id !== product_id || baseline.problem_id !== problem.id)) throw new Error('lean_comparison_product');
  const intervals = runtimeByShift(operatingRuntime(checkpoints, as_of),checkpoints);
  const version=Number(evidence_version)===2||[...occurrences,...entries].some(x=>Number(x.evidence_version)===2)?2:1;
  if (baseline && !(baseline.runtime_hours > 0)) {
    return { version,...(version===2?{time_basis:'production',status:'INCOMPLETE'}:{}), problem_id:problem.id, product_id, subject_id, cutoff, as_of, complete:false,
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
    exposure.intervals.at(-1).ended_at, exposure.collected_hours, { product_id, subject_id, mechanism: problem.mechanism,evidence_version:version }) : null;
  const before_metrics = baseline?.metrics || metrics(before), after_metrics = metrics(after);
  const compatible=!baseline||baseline.version===version;
  const complete = source_complete && before.complete && after.complete && compatible &&
    (!baseline||baseline.status!=='INCOMPLETE') && before_metrics?.status!=='INCOMPLETE' && after_metrics?.status!=='INCOMPLETE';
  const changes = Object.fromEntries(['occurrences_per_hour', 'loss_minutes', 'loss_minutes_per_hour', 'scrap_kg', 'scrap_rate'].map(key =>
    [key, complete ? metricChange(before_metrics?.[key], after_metrics?.[key], problem.threshold_percent ?? 10) : { percent: null, suggestion: 'INSUFFICIENT_DATA' }]));
  for (const key of ['lost_output','wip']) changes[key] = Object.fromEntries([...new Set([...Object.keys(before_metrics?.[key] || {}), ...Object.keys(after_metrics?.[key] || {})])].map(unit =>
    [unit, complete ? metricChange(before_metrics?.[key]?.[unit],after_metrics?.[key]?.[unit],problem.threshold_percent ?? 10) : { percent:null,suggestion:'INSUFFICIENT_DATA' }]));
  return { version,...(version===2?{time_basis:'production',status:complete?'READY':'INCOMPLETE',incompatible_evidence_versions:!compatible}:{}), problem_id: problem.id, product_id, subject_id, cutoff, as_of, complete, before, after, before_metrics, after_metrics, changes,
    threshold_percent: problem.threshold_percent ?? 10, source_complete, note: 'Separate metric suggestions; human verification is required. No combined score.' };
}
