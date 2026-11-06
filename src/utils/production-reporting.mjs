// M3A owns quantities, attribution, grouping and cursor validity. No arithmetic here.
import {exactJsonNumbers} from './exact-json.mjs';
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const hex = /^[0-9a-f]{64}$/;
const decimal = /^-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?$/;
const integer = /^(?:0|[1-9]\d*)$/;
const object = x => x !== null && typeof x === 'object' && !Array.isArray(x);
const invalid = () => { throw {code:'22023'}; };
const unavailable = () => { throw {code:'REPORTING_CONTRACT'}; };
const instant = x => typeof x === 'string' && /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d(?:\.\d{1,6})?(?:Z|[+-]\d\d:\d\d)$/.test(x) && Number.isFinite(Date.parse(x));
const date = x => typeof x === 'string' && /^\d{4}-\d\d-\d\d$/.test(x) && Number.isFinite(Date.parse(x)) && new Date(x).toISOString().slice(0,10) === x;
const count = x => {
  if (!((typeof x === 'number' && Number.isSafeInteger(x)) || (typeof x === 'string' && integer.test(x))) || !Number.isSafeInteger(Number(x)) || Number(x)<0) unavailable();
  return Number(x);
};
const revision = x => typeof x === 'string' && integer.test(x);
const cursorFields = ['version','factory','query_hash','source_revision','after','from_at','to_at'];
function validCursor(x, factory) {
  return object(x) && Object.keys(x).length===7 && cursorFields.every(k=>Object.hasOwn(x,k)) &&
    String(x.version)==='1' && x.factory===factory && hex.test(x.query_hash) && revision(x.source_revision) &&
    typeof x.after==='string' && x.after.length>0 && x.after.length<=1000 && instant(x.from_at) && instant(x.to_at) &&
    Buffer.byteLength(JSON.stringify(x))<=3000;
}

export function parseReportingQuery(query) {
  const allowed=['factory','reporting_version','mode','time_basis','from','to','from_at','to_at','product','line','entry','occurrence','page_size','cursor'];
  if ([...query.keys()].some(k=>!allowed.includes(k) || query.getAll(k).length!==1)) invalid();
  const factory=query.get('factory');
  if (!factory || !uuid.test(factory) || query.get('reporting_version')!=='3') invalid();
  const filters={reporting_version:3,mode:query.get('mode')??'entries',time_basis:query.get('time_basis')??'recorded',page_size:50};
  if (!['entries','summary','corrections'].includes(filters.mode) || !['recorded','production'].includes(filters.time_basis)) invalid();
  const size=query.get('page_size')??'50';
  if (!/^(?:[1-9]|[1-9]\d|100)$/.test(size)) invalid();
  filters.page_size=Number(size);
  for (const k of ['product','line','entry']) if (query.has(k)) {
    if (!uuid.test(query.get(k)??'')) invalid();
    filters[k]=query.get(k).toLowerCase();
  }
  if (filters.mode==='corrections' && !filters.entry) invalid();
  if (query.has('occurrence')) {
    if (!hex.test(query.get('occurrence')??'')) invalid();
    filters.occurrence=query.get('occurrence');
  }
  if ((query.has('from') || query.has('to')) && (query.has('from_at') || query.has('to_at'))) invalid();
  for (const k of ['from','to','from_at','to_at']) if (query.has(k)) {
    const value=query.get(k);
    if (!(k.endsWith('_at')?instant(value):date(value))) invalid();
    filters[k]=value;
  }
  if (filters.from && filters.to && (filters.from>filters.to || Date.parse(filters.to)-Date.parse(filters.from)>365*86400000)) invalid();
  if (filters.from_at && filters.to_at && (Date.parse(filters.from_at)>=Date.parse(filters.to_at) || Date.parse(filters.to_at)-Date.parse(filters.from_at)>366*86400000)) invalid();
  if (query.has('cursor')) {
    const value=query.get('cursor');
    if (!value || value.length>4000 || !/^[A-Za-z0-9_-]+$/.test(value)) invalid();
    try {
      filters.cursor=JSON.parse(Buffer.from(value,'base64url').toString('utf8'));
      if (!validCursor(filters.cursor,factory.toLowerCase())) invalid();
    } catch { invalid(); }
  }
  return {factory:factory.toLowerCase(),filters,sort_key:'date',sort_direction:'desc',page:1};
}

// Only the opt-in scalar RPC is transformed, before postgrest-js JSON.parse.
// Strings/escapes are indivisible tokens; no floating-point parsing of numbers.
export function exactReportingJson(text) {
  try { return exactJsonNumbers(text); } catch { unavailable(); }
}
export function reportingFetch(fetcher=globalThis.fetch) {
  return async (input,init) => {
    const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url);
    const response=await fetcher(input,init);
    if (response.ok && url.pathname.endsWith('/rest/v1/rpc/production_history') && (init?.method??'GET')==='GET') {
      let filters;
      try { filters=JSON.parse(url.searchParams.get('filters')??'null'); } catch { unavailable(); }
      if (filters?.reporting_version===3) {
        const body=exactReportingJson(await response.text());
        const headers=new Headers(response.headers);
        headers.delete('content-length');headers.delete('content-encoding');
        return new Response(body,{status:response.status,statusText:response.statusText,headers});
      }
    }
    return response;
  };
}

const entryDecimals=['weight_kg_per_unit','original_good','good','accepted_good','quality_rejected','original_scrap_kg','scrap_kg','original_discarded_quantity','discarded_quantity','original_wip','wip','produced_weight_kg','scrap_rate'];
const summaryDecimals=['good','accepted_good','declared_good','unallocated_good','declared_scrap_kg','unallocated_scrap_kg','scrap_kg','wip','reviewed_scrap_kg','scrap_rate'];
const auditDecimals=['previous_good','previous_scrap','corrected_good','corrected_scrap','previous_unfinished','corrected_unfinished','previous_scrap_kg','corrected_scrap_kg','previous_startup_kg','corrected_startup_kg'];
const auditFields=['id','factory_id','entry_id','reason','created_by','created_at','request_id','overproduction_confirmed','shift_changed','previous_shift_id','corrected_shift_id','previous_remaining_work','corrected_remaining_work','previous_occurrence_key','corrected_occurrence_key','previous_period_start','previous_period_end','corrected_period_start','corrected_period_end','attribution_changed',...auditDecimals];
const entryFields=['id','factory_id','request_id','request_code','item_id','item_code','product_id','product_code','product_name','product_name_ar','line_id','line_name','line_name_ar','work_center_id','unit','recorded_at','recorded_by','submitter_name','technician_id','technician_name','recording_kind','execution_key','execution_start','execution_finish','execution_evidence','current_item_status','current_execution_start','current_execution_finish','original_occurrence','effective_occurrence','original_period','effective_period','time_precision','allocation_known','weight_basis','standard_basis','shift_quantity_confirmed','scrap_rate_basis','source_id','input_lot_id','observation','lean_evidence','correction_count',...entryDecimals];
const summaryFields=['occurrence_key','occurrence','product_id','line_id','unit','records','attribution_complete','allocation_complete','unit_known','unknown_scrap_records','unknown_attribution_records','scrap_rate_basis',...summaryDecimals];
const pick=(x,keys)=>Object.fromEntries(keys.map(k=>{if(!Object.hasOwn(x,k)) unavailable();return [k,x[k]];}));
function decimals(row,keys) { for(const k of keys) if(row[k]!==null && !(typeof row[k]==='string' && decimal.test(row[k]))) unavailable(); }
function ids(row,keys) { for(const k of keys) if(row[k]!==null && !(typeof row[k]==='string' && uuid.test(row[k]))) unavailable(); }
function booleans(row,keys) { for(const k of keys) if(typeof row[k]!=='boolean') unavailable(); }
function occurrence(x,factory) {
  if(x===null)return null;
  if(!object(x) || x.factory_id!==factory || !hex.test(x.occurrence_key) || !date(x.business_date) || !instant(x.starts_at) || !instant(x.ends_at)) unavailable();
  const result=pick(x,['factory_id','occurrence_key','schedule_revision_id','shift_id','business_date','timezone','name','name_ar','starts_at','ends_at','identity_version']);
  ids(result,['schedule_revision_id','shift_id']);result.identity_version=count(result.identity_version);
  return result;
}
function period(x) {
  if(!object(x) || !Object.hasOwn(x,'start') || !Object.hasOwn(x,'end') || [x.start,x.end].some(t=>t!==null&&!instant(t))) unavailable();
  return {start:x.start,end:x.end};
}
export function reportingResponse(data,args) {
  const f=args.factory,q=args.filters;
  if(!object(data) || String(data.contract_version)!=='3' || String(data.evidence_contract_version)!=='2' || data.factory_id!==f ||
    data.mode!==q.mode || data.time_basis!==q.time_basis || data.unknown_scope!=='RECORDED_WINDOW' || !revision(data.source_revision) ||
    !instant(data.from_at) || !instant(data.to_at) || !Array.isArray(data.rows) || count(data.page_size)!==q.page_size || data.rows.length>q.page_size) unavailable();
  booleans(data,['complete','attribution_complete','allocation_complete']);
  if(data.complete ? data.next_cursor!==null : !validCursor(data.next_cursor,f) || data.rows.length!==q.page_size) unavailable();
  const rows=data.rows.map(input=>{
    if(!object(input))unavailable();
    if(q.mode==='entries') {
      const row=pick(input,entryFields);decimals(row,entryDecimals);
      if(row.factory_id!==f || !uuid.test(row.id) || !instant(row.recorded_at) || !['meter','piece','kg',null].includes(row.unit) || !['SHIFT_PERIOD','UNKNOWN'].includes(row.time_precision) || !['PROTECTED_PLAN_EXECUTION','UNKNOWN'].includes(row.execution_evidence))unavailable();
      ids(row,['request_id','item_id','product_id','line_id','work_center_id','recorded_by','technician_id','source_id','input_lot_id']);
      booleans(row,['allocation_known']);row.correction_count=count(row.correction_count);
      row.original_occurrence=occurrence(row.original_occurrence,f);row.effective_occurrence=occurrence(row.effective_occurrence,f);
      row.original_period=period(row.original_period);row.effective_period=period(row.effective_period);
      row.observation=pick(row.observation,['id','status','precision','occurred_at','occurrence_key','period_start','period_end']);
      ids(row.observation,['id']);
      if(!['UNOBSERVED','PENDING','REVIEWED'].includes(row.observation.status))unavailable();
      if(Object.hasOwn(input.observation,'review_current')) {
        if(typeof input.observation.review_current!=='boolean')unavailable();
        row.observation.review_current=input.observation.review_current;
      }
      if(row.lean_evidence!==null) {
        row.lean_evidence=pick(row.lean_evidence,['version','time_basis','reviewed_scrap_kg','allocation_known','weight_basis','comparison_status']);
        if(String(row.lean_evidence.version)!=='2' || row.lean_evidence.time_basis!==q.time_basis || row.lean_evidence.comparison_status!=='NOT_CALCULATED') unavailable();
        decimals(row.lean_evidence,['reviewed_scrap_kg']);booleans(row.lean_evidence,['allocation_known']);row.lean_evidence.version=2;
      }
      return row;
    }
    if(q.mode==='summary') {
      const row=pick(input,summaryFields);decimals(row,summaryDecimals);ids(row,['product_id','line_id']);
      if(!['meter','piece','kg',null].includes(row.unit) || row.occurrence_key!==null&&!hex.test(row.occurrence_key))unavailable();
      booleans(row,['attribution_complete','allocation_complete','unit_known']);
      for(const k of ['records','unknown_scrap_records','unknown_attribution_records'])row[k]=count(row[k]);
      row.occurrence=occurrence(row.occurrence,f);return row;
    }
    const row=pick(input,auditFields);decimals(row,auditDecimals);
    if(row.factory_id!==f || row.entry_id!==q.entry || !instant(row.created_at))unavailable();
    ids(row,['id','entry_id','created_by','request_id','previous_shift_id','corrected_shift_id']);
    booleans(row,['overproduction_confirmed','shift_changed','attribution_changed']);return row;
  });
  return {...pick(data,['factory_id','mode','time_basis','from_at','to_at','unknown_scope','source_revision','complete','attribution_complete','allocation_complete']),
    contract_version:3,evidence_contract_version:2,total:count(data.total),page_size:q.page_size,
    unknown_attribution_records:count(data.unknown_attribution_records),rows,
    next_cursor:data.next_cursor===null?null:Buffer.from(JSON.stringify({...data.next_cursor,version:1}),'utf8').toString('base64url')};
}
