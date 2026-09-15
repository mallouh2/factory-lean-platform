/** Clip intervals to the reporting window so overnight and open stops are counted correctly. */
export function downtimeMinutes(event, from, to, now = Date.now()) {
  const start = Math.max(
    new Date(event.started_at).getTime(),
    new Date(from).getTime(),
  );
  const end = Math.min(
    event.ended_at ? new Date(event.ended_at).getTime() : now,
    new Date(to).getTime(),
    now,
  );
  return Number.isFinite(start) && Number.isFinite(end)
    ? Math.max(0, end - start) / 60000
    : 0;
}
export function calculateOee(observation) {
  if (!observation) return null;
  const {
    planned_seconds: p,
    run_seconds: r,
    ideal_cycle_seconds: c,
    total_count: t,
    good_count: g,
  } = observation;
  if (
    ![p, r, c, t, g].every(
      (x) => typeof x === "number" && Number.isFinite(x),
    ) ||
    p <= 0 ||
    r <= 0 ||
    c <= 0 ||
    t <= 0 ||
    g < 0 ||
    g > t ||
    r > p ||
    c * t > r
  )
    return null;
  return {
    availability: r / p,
    performance: (c * t) / r,
    quality: g / t,
    oee: (r / p) * ((c * t) / r) * (g / t),
  };
}
export function pareto(events, value, group) {
  const sums = new Map();
  for (const e of events) {
    const k = group(e);
    sums.set(k, (sums.get(k) || 0) + value(e));
  }
  const total = [...sums.values()].reduce((a, b) => a + b, 0);
  let cumulative = 0;
  return [...sums]
    .sort((a, b) => b[1] - a[1])
    .map(([key, minutes]) => {
      cumulative += minutes;
      return {
        key,
        minutes,
        percent: total ? (minutes / total) * 100 : 0,
        cumulative: total ? (cumulative / total) * 100 : 0,
      };
    });
}
export function csvCell(value) {
  const text = String(value ?? "");
  const safe = /^[\s]*[=+\-@\t\r]/.test(text) ? "'" + text : text;
  return '"' + safe.replaceAll('"', '""') + '"';
}
/** Calendar boundaries use the factory IANA zone, including DST, rather than the browser zone. */
export function zonedMidnight(date, zone) {
  const [y, m, d] = date.split("-").map(Number);
  let utc = Date.UTC(y, m - 1, d);
  for (let i = 0; i < 4; i++) {
    const parts = new Intl.DateTimeFormat("en-GB", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(utc));
    const p = Object.fromEntries(parts.map((x) => [x.type, x.value]));
    const shown = Date.UTC(
      +p.year,
      +p.month - 1,
      +p.day,
      +p.hour,
      +p.minute,
      +p.second,
    );
    utc += Date.UTC(y, m - 1, d) - shown;
  }
  return new Date(utc).toISOString();
}
export function reportPeriod(
  period,
  zone,
  now = new Date(),
  customFrom = "",
  customTo = "",
) {
  const today = new Intl.DateTimeFormat("en-CA", {
    timeZone: zone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(now);
  let start = new Date(today + "T12:00:00Z"),
    end = new Date(start);
  end.setUTCDate(end.getUTCDate() + 1);
  if (period === "yesterday") {
    start.setUTCDate(start.getUTCDate() - 1);
    end.setUTCDate(end.getUTCDate() - 1);
  }
  if (period === "week")
    start.setUTCDate(start.getUTCDate() - ((start.getUTCDay() + 6) % 7));
  if (period === "month") start.setUTCDate(1);
  if (period === "custom" && customFrom && customTo) {
    start = new Date(customFrom + "T12:00:00Z");
    end = new Date(customTo + "T12:00:00Z");
    end.setUTCDate(end.getUTCDate() + 1);
  }
  return {
    from: zonedMidnight(start.toISOString().slice(0, 10), zone),
    to: zonedMidnight(end.toISOString().slice(0, 10), zone),
  };
}

export function formatLocalInput(iso, zone) {
  const parts = new Intl.DateTimeFormat('en-GB', {timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).formatToParts(new Date(iso));
  const p=Object.fromEntries(parts.map(x=>[x.type,x.value]));
  return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`;
}
/** Reject nonexistent local times during DST changes instead of silently moving a production event. */
export function localDateTimeToUtc(value, zone) {
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}$/.test(value)) throw new Error('invalidDate');
  const wanted=Date.parse(value+':00Z');
  let utc=wanted;
  for(let i=0;i<5;i++) utc+=wanted-Date.parse(formatLocalInput(new Date(utc).toISOString(),zone)+':00Z');
  const result=new Date(utc).toISOString();
  if(formatLocalInput(result,zone)!==value) throw new Error('invalidDate');
  return result;
}

/** Utilization is running time / observed time, not OEE availability or a guessed shift calendar. */
export function statusUtilization(events, center, from, to, now=Date.now()) {
  const history=events.filter(e=>e.work_center_id===center).sort((a,b)=>Date.parse(a.created_at)-Date.parse(b.created_at));
  const start=Date.parse(from),end=Math.min(Date.parse(to),now);let running=0,observed=0;
  for(let i=0;i<history.length;i++){
    const a=Math.max(start,Date.parse(history[i].created_at)),b=Math.min(end,i+1<history.length?Date.parse(history[i+1].created_at):end);
    if(b>a){observed+=b-a;if(history[i].new_status==='running')running+=b-a;}
  }
  return observed ? {percent:running/observed*100,observedMinutes:observed/60000,runningMinutes:running/60000,coverage:(end>start?observed/(end-start):0)}:null;
}
