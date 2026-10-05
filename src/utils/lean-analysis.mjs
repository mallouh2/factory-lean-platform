// Analysis helpers consume persisted measurements; they never calculate Production Loss.
import { evaluateFlow } from './production-flow.mjs';
import { formatLocalInput, localDateTimeToUtc } from './manufacturing.mjs';
const finite = value => value !== null && value !== undefined && value !== '' && Number.isFinite(Number(value));
const nonnegative = value => finite(value) && Number(value) >= 0;
const moment = value => typeof value === 'number' ? value : Date.parse(value);

export function leanProblemIdentity({ factory_id, mechanism, machine_id, line_id, product_id, approved_cause_id }) {
  if (!factory_id || !approved_cause_id) throw new Error('lean_identity_unreviewed');
  if (mechanism === 'downtime' && machine_id) return JSON.stringify([factory_id, mechanism, machine_id, approved_cause_id]);
  if (mechanism === 'scrap' && line_id && product_id) return JSON.stringify([factory_id, mechanism, line_id, product_id, approved_cause_id]);
  throw new Error('lean_identity_invalid');
}

export function producedWeight({ good, newly_recorded_wip, unit, weight_unit, kg_per_unit }) {
  if (!nonnegative(good) || !nonnegative(newly_recorded_wip)) throw new Error('lean_quantity_invalid');
  if (unit === 'kg') return Number(good) + Number(newly_recorded_wip);
  if (!['meter', 'piece'].includes(unit) || unit !== weight_unit || !finite(kg_per_unit) || Number(kg_per_unit) <= 0) return null;
  return (Number(good) + Number(newly_recorded_wip)) * Number(kg_per_unit);
}

export function scrapRate(scrap_kg, produced_kg) {
  if (!nonnegative(scrap_kg)) throw new Error('lean_scrap_invalid');
  return finite(produced_kg) && Number(produced_kg) > 0 ? Number(scrap_kg) * 100 / Number(produced_kg) : null;
}

// One allowance per actual startup ID, shared by all declarations for that startup.
export function startupPerformance(events, approved_kg) {
  if (approved_kg !== null && !nonnegative(approved_kg)) throw new Error('lean_standard_invalid');
  const startups = new Map();
  for (const event of events) {
    if (!event.startup_id || !nonnegative(event.scrap_kg)) throw new Error('lean_startup_invalid');
    startups.set(event.startup_id, (startups.get(event.startup_id) || 0) + Number(event.scrap_kg));
  }
  const total_kg = [...startups.values()].reduce((a, b) => a + b, 0);
  const expected_kg = !startups.size ? 0 : approved_kg === null ? null : [...startups.values()].reduce((sum, kg) => sum + Math.min(kg, Number(approved_kg)), 0);
  return { startups: startups.size, total_kg, expected_kg, excess_kg: expected_kg === null ? null : total_kg - expected_kg,
    observed_kg_per_startup: startups.size ? total_kg / startups.size : null, approved_kg };
}

export function abnormalScrap({ total_scrap_kg, produced_kg, startup_events = [], startup_standard_kg = null, running_standard_percent = null }) {
  if (!nonnegative(total_scrap_kg)) throw new Error('lean_scrap_invalid');
  const startup = startupPerformance(startup_events, startup_standard_kg);
  if (startup.total_kg > Number(total_scrap_kg)) throw new Error('lean_scrap_invalid');
  if (running_standard_percent !== null && !nonnegative(running_standard_percent)) throw new Error('lean_standard_invalid');
  const running_kg = Number(total_scrap_kg) - startup.total_kg;
  const adjusted_kg = startup.expected_kg === null ? null : Number(total_scrap_kg) - startup.expected_kg;
  const running_rate = adjusted_kg === null ? null : scrapRate(adjusted_kg, produced_kg);
  const gaps = [];
  if (startup.startups && startup_standard_kg === null) gaps.push('startup_standard');
  if (running_standard_percent === null) gaps.push('running_standard');
  if (running_rate === null) gaps.push('produced_weight');
  return { startup, running_kg, adjusted_kg, running_rate, gaps, abnormal_startup: startup.excess_kg === null ? null : startup.excess_kg > 0,
    abnormal_running: running_rate === null || running_standard_percent === null ? null : running_rate > Number(running_standard_percent) };
}

/** @param {Array<Record<string, any>>} actions @param {Record<string, any>|null} verification */
export function initiativeStatus(actions, verification = null) {
  if (verification?.derived_status) return verification.derived_status;
  if (verification?.confirmed_at || verification?.verified_at) return 'VERIFIED';
  const required = actions.filter(a => a.status !== 'CANCELLED');
  if (actions.length && required.every(a => a.status === 'COMPLETED')) return 'AWAITING_VERIFICATION';
  if (actions.some(a => a.status !== 'OPEN')) return 'IN_PROGRESS';
  return 'OPEN';
}

export function recurrenceAfterVerification(occurrences, verified_at, now) {
  const from = moment(verified_at), until = Math.min(from + 30 * 86400000, moment(now));
  if (!Number.isFinite(from) || !Number.isFinite(until) || until < from) throw new Error('lean_period_invalid');
  const ids = new Set(occurrences.filter(o => moment(o.occurred_at) > from && moment(o.occurred_at) <= until).map(o => o.event_id));
  return { count: ids.size, recurred: ids.size >= 2, watch_until: new Date(from + 30 * 86400000).toISOString() };
}

export function metricChange(before, after, threshold_percent = 10) {
  if (!nonnegative(threshold_percent)) throw new Error('lean_threshold_invalid');
  if (!nonnegative(before) || !nonnegative(after)) return { percent: null, suggestion: 'INSUFFICIENT_DATA' };
  if (Number(before) === 0) return { percent: null, suggestion: Number(after) === 0 ? 'NO_MEANINGFUL_CHANGE' : 'WORSE' };
  const percent = (Number(after) - Number(before)) * 100 / Number(before);
  return { percent, suggestion: percent < -Number(threshold_percent) ? 'IMPROVED' : percent > Number(threshold_percent) ? 'WORSE' : 'NO_MEANINGFUL_CHANGE' };
}

// Half-open timestamped runtime intervals are authoritative inputs, never inferred from calendar time.
export function comparableExposure(intervals, { product_id, subject_id, cutoff, direction, desired_hours }) {
  const boundary = moment(cutoff);
  if (!product_id || !subject_id || !Number.isFinite(boundary) || !finite(desired_hours) || Number(desired_hours) <= 0 || !['before', 'after'].includes(direction)) throw new Error('lean_comparison_invalid');
  const desired_ms = Number(desired_hours) * 3600000;
  const matching = intervals.filter(i => i.product_id === product_id && i.subject_id === subject_id).map(i => {
    const from = moment(i.started_at), to = moment(i.ended_at);
    if (!Number.isFinite(from) || !Number.isFinite(to) || to <= from) throw new Error('lean_runtime_invalid');
    return { from: direction === 'after' ? Math.max(from, boundary) : from, to: direction === 'before' ? Math.min(to, boundary) : to };
  }).filter(i => i.to > i.from).sort((a, b) => a.from - b.from);
  for (let i = 1; i < matching.length; i++) if (matching[i].from < matching[i - 1].to) throw new Error('lean_runtime_overlap');
  if (direction === 'before') matching.reverse();
  let collected_ms = 0;
  const selected = [];
  for (const i of matching) {
    const take = Math.min(i.to - i.from, desired_ms - collected_ms);
    if (take <= 0) break;
    selected.push({ started_at: new Date(direction === 'before' ? i.to - take : i.from).toISOString(), ended_at: new Date(direction === 'before' ? i.to : i.from + take).toISOString() });
    collected_ms += take;
  }
  return { intervals: selected.sort((a, b) => a.started_at.localeCompare(b.started_at)), desired_hours: Number(desired_hours),
    collected_hours: collected_ms / 3600000, remaining_hours: (desired_ms - collected_ms) / 3600000, complete: collected_ms === desired_ms };
}

// Checkpoints contain server-persisted active execution, physical state, OPEN transfers and pause truth.
export function operatingRuntime(checkpoints, until) {
  const end = moment(until);
  if (!Number.isFinite(end)) throw new Error('lean_period_invalid');
  const byTime = new Map();
  for (const row of [...checkpoints].sort((a, b) => moment(a.captured_at) - moment(b.captured_at) || Number(a.id) - Number(b.id))) {
    if (!Number.isFinite(moment(row.captured_at))) throw new Error('lean_runtime_invalid');
    byTime.set(moment(row.captured_at), row);
  }
  const history = [...byTime.values()], intervals = [];
  for (let index = 0; index < history.length; index++) {
    const sample = history[index], from = moment(sample.captured_at), to = Math.min(index + 1 < history.length ? moment(history[index + 1].captured_at) : end, end);
    if (to <= from) continue;
    const { centers = [], stops = [], transfers = [], orders = [], lines = [] } = sample.context;
    const points = new Set([from, to]);
    for (const value of [...orders.flatMap(o => [o.actual_start, o.actual_finish]), ...lines.map(l => l.paused_at)]) {
      const at = moment(value);
      if (at > from && at < to) points.add(at);
    }
    for (const center of centers.filter(c => c.dependency_mode === 'buffer')) {
      const stop = stops.find(s => s.work_center_id === center.id && !s.ended_at);
      const away = transfers.find(t => t.alternative_id === center.id && !t.ended_at);
      const expiry = moment(stop?.started_at || away?.created_at) + Number(center.buffer_minutes) * 60000;
      if (expiry > from && expiry < to) points.add(expiry);
    }
    const boundaries = [...points].sort((a, b) => a - b);
    for (let segment = 0; segment < boundaries.length - 1; segment++) {
      const start = boundaries[segment], finish = boundaries[segment + 1], flow = evaluateFlow(centers, stops, transfers, start + 1);
      for (const job of orders.filter(o => o.status === 'active' && o.actual_start && moment(o.actual_start) <= start && (!o.actual_finish || moment(o.actual_finish) > start))) {
        for (const center of centers.filter(c=>c.dependency_mode==='independent' && !c.archived && c.order_id===job.id && c.status==='running' && flow[c.id]?.state!=='blocked' && !transfers.some(t=>t.alternative_id===c.id&&!t.ended_at))) {
          intervals.push({product_id:job.product_id,item_id:job.id,subject_id:center.id,started_at:new Date(start).toISOString(),ended_at:new Date(finish).toISOString()});
        }
        const line = lines.find(l => l.id === job.line_id);
        if (!line || line.archived || line.paused_at && moment(line.paused_at) <= start) continue;
        const members = centers.filter(c => c.line_id === line.id && !c.archived && c.dependency_mode !== 'independent');
        if (!members.length || members.some(c => (flow[c.id]?.homeState || flow[c.id]?.state) === 'blocked')) continue;
        const operating = members.filter(c => {
          if (['running'].includes(c.status) && !transfers.some(t => t.alternative_id === c.id && t.original_id !== c.id && !t.ended_at && centers.find(x => x.id === t.original_id)?.line_id !== line.id)) return true;
          const transfer = transfers.find(t => t.original_id === c.id && !t.ended_at);
          return transfer && centers.find(a => a.id === transfer.alternative_id)?.status === 'running' && flow[c.id]?.state !== 'blocked';
        });
        if (!operating.length) continue;
        if (members.some(c => ['blocking', 'buffer'].includes(c.dependency_mode) && c.impact_scope !== 'none' &&
          !operating.includes(c) && (flow[c.id]?.homeState || flow[c.id]?.state) !== 'bufferActive')) continue;
        const interval = { product_id: job.product_id, item_id: job.id, started_at: new Date(start).toISOString(), ended_at: new Date(finish).toISOString() };
        intervals.push({ ...interval, subject_id: line.id });
        for (const center of operating) intervals.push({ ...interval, subject_id: center.id });
      }
    }
  }
  return intervals;
}

/** Shift windows are taken from immutable runtime checkpoints, never today's configuration. */
export function runtimeByShift(intervals, checkpoints) {
  const result=[];
  for(const interval of intervals){
    const context=[...checkpoints].reverse().find(x=>moment(x.captured_at)<=moment(interval.started_at))?.context;
    const shifts=context?.shifts?.filter(x=>!x.archived) || [],zone=context?.timezone||'UTC';
    if(!shifts.length){result.push({...interval,shift_id:null});continue;}
    const from=moment(interval.started_at),to=moment(interval.ended_at),boundaries=new Set([from,to]);
    let day=formatLocalInput(interval.started_at,zone).slice(0,10),last=formatLocalInput(interval.ended_at,zone).slice(0,10);
    while(day<=last){
      for(const shift of shifts)for(const value of [shift.start_time,shift.end_time]){
        if(!value)continue;
        try{const boundary=moment(localDateTimeToUtc(day+'T'+String(value).slice(0,5),zone))+Number(String(value).split(':')[2]||0)*1000;if(boundary>from&&boundary<to)boundaries.add(boundary);}catch{ /* Nonexistent DST boundary leaves this segment unattributed. */ }
      }
      day=new Date(Date.parse(day+'T12:00:00Z')+86400000).toISOString().slice(0,10);
    }
    const points=[...boundaries].sort((a,b)=>a-b);
    for(let index=0;index<points.length-1;index++){
      const local=new Intl.DateTimeFormat('en-GB',{timeZone:zone,hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).format(new Date((points[index]+points[index+1])/2));
      const matching=shifts.filter(s=>s.start_time<s.end_time?local>=s.start_time&&local<s.end_time:local>=s.start_time||local<s.end_time);
      result.push({...interval,started_at:new Date(points[index]).toISOString(),ended_at:new Date(points[index+1]).toISOString(),shift_id:matching.length===1?matching[0].id:null});
    }
  }
  return result;
}
