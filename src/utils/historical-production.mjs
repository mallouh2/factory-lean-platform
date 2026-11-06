import {exactJsonNumbers} from './exact-json.mjs';
import {recordingBody} from './production-recording-intent.mjs';
/** @param {string|null} [supersedes] */
export function historicalBody(factory,request,measurement,occurrence,supersedes=null){
 const ordinary=recordingBody(factory,request,measurement),marker='"payload":',raw=ordinary.slice(ordinary.indexOf(marker)+marker.length,-2);
 return `{"factory":${JSON.stringify(factory)},"operation":"SUBMIT","request_id":${JSON.stringify(request)},"payload":{"measurement":${raw},"business_date":${JSON.stringify(occurrence.business_date)},"occurrence_key":${JSON.stringify(occurrence.occurrence_key)},"supersedes":${JSON.stringify(supersedes)}}}`;
}
export const historicalScope=(factory,actor)=>`factory-lean:historical:v1:${factory}:${actor}`;

export function exactHistoricalPayload(raw,body){const original=JSON.parse(exactJsonNumbers(raw));for(const key of ['good','discarded_quantity','scrap_kg','startup_kg','unfinished','input_quantity'])if(typeof body.payload.measurement[key]==='number')body.payload.measurement[key]=JSON.rawJSON(original.payload.measurement[key]);}
