export function maintenanceReaderArgs(params) {
  const mode=params.get('mode');
  const fields={preview:['start','end','request_revision','schedule_revision','context_hash'],
    gaps:['start','end','request_revision','schedule_revision','window_minutes','limit','after_start','context_hash'],
    history:['limit','before_revision','through_revision']}[mode];
  if (!fields || [...params.keys()].some(key=>!['factory','request','mode',...fields].includes(key))) throw {code:'22023'};
  const uuid=key=>{const v=params.get(key);if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v||''))throw {code:'22023'};return v;};
  const integer=(key,min,max,fallback=null)=>{const value=params.get(key);if(value===null)return fallback;
    const n=Number(value);if(!/^\d+$/.test(value)||!Number.isSafeInteger(n)||n<min||n>max)throw {code:'22023'};return n;};
  const timestamp=(key,required=false)=>{const value=params.get(key);if(value===null&&!required)return null;
    if(!/^\d{4}-\d\d-\d\dT\d\d:\d\d(?::\d\d(?:\.\d{1,3})?)?(?:Z|[+-]\d\d:\d\d)$/.test(value||'')||!Number.isFinite(Date.parse(value)))throw {code:'22023'};return value;};
  const args={factory:uuid('factory'),maintenance_request:uuid('request')};
  if(mode==='history')return {mode,args:{...args,page_size:integer('limit',1,50,25),before_revision:integer('before_revision',1,2147483647),through_revision:integer('through_revision',0,2147483647)}};
  const request=integer('request_revision',1,2147483647),schedule=integer('schedule_revision',0,2147483647),hash=params.get('context_hash');
  if(request===null||schedule===null||(hash!==null&&!/^[a-f0-9]{64}$/.test(hash)))throw {code:'22023'};
  const common={...args,expected_request_revision:request,expected_schedule_revision:schedule,expected_context_hash:hash};
  const start=timestamp('start',true),end=timestamp('end',mode==='gaps');
  if(end&&Date.parse(end)<=Date.parse(start))throw {code:'22023'};
  if(mode==='preview')return {mode,args:{...common,candidate_start:start,candidate_end:end}};
  if(Date.parse(end)-Date.parse(start)>31*86400000)throw {code:'22023'};
  const after=timestamp('after_start');if(after&&(!hash||Date.parse(after)<Date.parse(start)||Date.parse(after)>=Date.parse(end)))throw {code:'22023'};
  return {mode,args:{...common,search_start:start,search_end:end,window_minutes:integer('window_minutes',1,2147483647),result_limit:integer('limit',1,20,10),after_start:after}};
}
