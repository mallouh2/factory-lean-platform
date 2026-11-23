import { abnormalScrap } from './lean-analysis.mjs';

// Attention is relative to the entire filtered population, before pagination.
// Include ties at the top-fifth boundary; a singleton or uniform population has no outlier.
export function relativeAttention(rows, metric) {
  const values = rows.map(row => row[metric]).filter(value => value != null && Number.isFinite(Number(value)) && Number(value) >= 0).map(Number).sort((a,b) => b-a);
  if (values.length < 2 || values[0] === values.at(-1)) return null;
  const boundary = values[Math.ceil(values.length * .2)-1];
  return boundary > 0 && boundary > values.at(-1) ? boundary : null;
}

export function leanDisplayStatus(row) {
  if (!row.initiative) return 'OCCURRENCE';
  if (row.initiative.verified_at) return 'VERIFIED';
  if (row.initiative.completed_at) return 'AWAITING_VERIFICATION';
  return 'IN_PROGRESS';
}

// Rank available loss evidence across the entire filtered result, before paging.
export function leanLossRanking(rows, limit = 6) {
  const causes = new Map();
  for (const row of rows) {
    const minutes = Number(row.loss_minutes);
    if (row.mechanism !== 'downtime' || !row.cause_id || !Number.isFinite(minutes) || minutes <= 0) continue;
    const cause = causes.get(row.cause_id) || { id: row.cause_id, name: row.cause, name_ar: row.cause_ar, minutes: 0 };
    cause.minutes += minutes;
    causes.set(cause.id, cause);
  }
  const ranked = [...causes.values()].sort((a, b) => b.minutes - a.minutes || String(a.id).localeCompare(String(b.id)));
  const total = ranked.reduce((sum, cause) => sum + cause.minutes, 0);
  let cumulative = 0;
  return ranked.slice(0, limit).map(cause => ({
    ...cause,
    cumulative: (cumulative += cause.minutes) / total,
  }));
}

// Reuse approved recording snapshots and the existing abnormal-Scrap calculation.
// Earlier declarations consume allowance even when outside the visible analysis period.
export function recordingScrapAttention(entries, startups) {
  const standards = new Map(startups.map(startup => [startup.id,startup.standard_kg]));
  const used = new Map(), attention = new Map();
  for (const entry of [...entries].sort((a,b) => Date.parse(a.created_at)-Date.parse(b.created_at) || String(a.id).localeCompare(String(b.id)))) {
    const id=entry.lean_startup_id, mass=entry.effective_scrap_kg, startupMass=Number(entry.effective_startup_kg || 0);
    const previous=used.get(id)||0, standard=id?standards.get(id):null;
    if(id)used.set(id,previous+startupMass);
    if(mass==null) { attention.set(entry.id,false); continue; }
    const assessment=abnormalScrap({total_scrap_kg:mass,produced_kg:entry.produced_weight_kg,
      running_standard_percent:entry.running_standard_percent ?? null,
      startup_events:id?[{startup_id:id,scrap_kg:startupMass}]:[],
      startup_standard_kg:id&&standard!=null?Math.max(0,Number(standard)-previous):null});
    attention.set(entry.id,assessment.abnormal_running===true || (id&&standard!=null&&previous+startupMass>Number(standard))===true);
  }
  return attention;
}

/** @param {any[]} rows @param {{entries?:any[],startups?:any[],links?:any[],from?:string,to?:string}} options */
export function annotateLeanAttention(rows, { entries=[], startups=[], links=[], from, to }={}) {
  const loss=relativeAttention(rows,'loss_minutes'), frequency=relativeAttention(rows,'frequency');
  const declarations=recordingScrapAttention(entries,startups);
  const inPeriod=link=>Date.parse(link.occurred_at)>=Date.parse(from)&&Date.parse(link.occurred_at)<Date.parse(to);
  return rows.map(row=>({...row,display_status:leanDisplayStatus(row),attention:{
    loss:loss!=null&&row.loss_minutes!=null&&Number(row.loss_minutes)>=loss,
    frequency:frequency!=null&&row.frequency!=null&&Number(row.frequency)>=frequency,
    // Unlinked High-Scrap rows are already gated by the authoritative SQL assessment.
    scrap:row.mechanism==='scrap'&&Number(row.scrap_kg)>0 || links.some(link=>link.downtime_id&&link.approved_cause_id===row.cause_id&&
      (row.event_ids||[]).includes(link.downtime_id)&&inPeriod(link)&&declarations.get(link.entry_id)===true),
  }}));
}
