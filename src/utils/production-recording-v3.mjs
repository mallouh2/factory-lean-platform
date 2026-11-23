import {exactJsonNumbers} from './exact-json.mjs';
const hex = value => typeof value === 'string' && /^[0-9a-f]{64}$/.test(value);
const uuid = value => typeof value === 'string' && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
export function recordingContextValid(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).sort().join(',') === 'context_hash,current_shift_quantity_confirmed,execution_key,occurrence_key,version' &&
    value.version === 3 && typeof value.current_shift_quantity_confirmed === 'boolean' &&
    ['execution_key','occurrence_key','context_hash'].every(key => hex(value[key]));
}
// Retain numeric JSON on the wire after ordinary shape/type validation. SQL's
// canonical request contract still receives numbers, never quantity strings.
export function exactRecordingPayload(raw,payload){
 const exact=JSON.parse(exactJsonNumbers(raw)).args.payload;
 for(const key of ['good','discarded_quantity','scrap_kg','startup_kg','unfinished','input_quantity'])
  if(typeof payload[key]==='number')payload[key]=JSON.rawJSON(exact[key]);
}
// V3 receipt/recovery quantities use the same exact-string transport as History.
// Only integer protocol versions are restored; persisted SQL evidence is untouched.
export function recordingFetch(fetcher=globalThis.fetch){
 return async(input,init)=>{
  const url=new URL(typeof input==='string'?input:input instanceof URL?input.href:input.url),response=await fetcher(input,init);
  if(!response.ok||!['plan_measurement_makeup','historical_production_read','historical_production_command','record_lean_production','production_recording_request_status','record_manufactured_output','manufactured_output_read','manufactured_output_command','manufactured_receiving_read','receive_manufactured_output','manufactured_completion_read','plan_manufactured_completion','revise_manufactured_completion','reconcile_manufactured_output','manufactured_receiving_context','manufactured_completion_context','manufactured_output_order_read'].some(name=>url.pathname.endsWith('/rest/v1/rpc/'+name)))return response;
  const data=JSON.parse(exactJsonNumbers(await response.text()),(key,value)=>['contract_version','version','schema_contract_version'].includes(key)&&typeof value==='string'&&/^\d+$/.test(value)?Number(value):value);
  const headers=new Headers(response.headers);headers.delete('content-length');headers.delete('content-encoding');
  return new Response(JSON.stringify(data),{status:response.status,statusText:response.statusText,headers});
 };
}
export function parseRecordingStatusQuery(query) {
  if ([...query.keys()].some(key => !['factory','request_id'].includes(key)) ||
      !['factory','request_id'].every(key => query.getAll(key).length === 1 && uuid(query.get(key))))
    throw {code:'22023'};
  return {factory:query.get('factory').toLowerCase(),request_id:query.get('request_id').toLowerCase()};
}
export function recordingFailure(error) {
  const message = error instanceof Error ? error.message : error?.message;
  const code = error?.code;
  if (message === 'unauthorized') return {status:401,error:'unauthorized'};
  if (code === '42501' || message === 'permission_denied') return {status:403,error:'permissionError'};
  if (message === 'output_paused' || message === 'output_enrollment_required') return {status:409,error:message==='output_paused'?'outputPaused':'outputEnrollmentRequired',reason:message,outcome:'REJECTED'};
  if (message === 'output_carryover_unsupported') return {status:422,error:'outputCarryoverUnsupported',reason:message,outcome:'REJECTED'};
  if (message === 'lean_startup_execution') return {status:422,error:'prv3StartupTimeInvalid',reason:message,outcome:'REJECTED'};
  if (['production_stock_shortage','production_stock_legacy_review','production_stock_recipe_review'].includes(message)) return {status:422,error:message,reason:message,outcome:'REJECTED'};
  if (code === '40001') return {status:409,error:message === 'request_conflict' ? 'recordingRequestConflict' : 'recordingContextChanged',outcome:'REJECTED'};
  if (code === '55000') return {status:503,error:message==='recording_disabled'?'prv3LateDisabled':'recordingUnavailable',outcome:'REJECTED'};
  const reasons={recording_shift_expired:'SHIFT_EXPIRED',recording_shift_unavailable:'SHIFT_UNAVAILABLE',recording_shift_declaration:'SHIFT_DECLARATION_REQUIRED',
    recording_overproduction_confirmation:'OVERPRODUCTION_CONFIRMATION_REQUIRED',recording_invalid_unit:'UNIT_UNAVAILABLE',unfinished_insufficient:'WIP_UNAVAILABLE',
    unfinished_conservation:'WIP_CONSERVATION',maintenance_capacity_reserved:'MAINTENANCE_HOLD',invalid_input:'INVALID_PAYLOAD'};
  if (['22023','22003','22007','22P02','23514'].includes(code) || Object.hasOwn(reasons,message))
    return {status:422,error:'recordingValidation',...(reasons[message]?{reason:reasons[message]}:{}),outcome:'REJECTED'};
  // A transport/server failure cannot prove whether a write committed.
  return {status:503,error:'dataWarning',outcome:'UNKNOWN'};
}
