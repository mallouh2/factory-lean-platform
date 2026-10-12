import { abnormalScrap, scrapRate } from './lean-analysis.mjs';
import { decimalCompare } from './quality-quantities.mjs';
const mass = value => ['number','string'].includes(typeof value) && String(value).trim() !== '' && Number.isFinite(Number(value)) && Number(value) >= 0;

// One historical entry, not a shift aggregate. Inputs come only from the protected
// reader. Production reprocessing KG is already included; never add rework snapshots.
export function qualityScrapState(input) {
 const s = input && typeof input === 'object' ? input : {};
 // Actual KG ratio needs no Line standard or startup comparison context. The
 // reader supplies captured mass or a derivation from captured historical weight.
 const validMass = s.version === 1 && ['meter','piece'].includes(s.unit) && mass(s.produced_kg) && Number(s.produced_kg)>0;
 const validScrap = mass(s.production_scrap_kg) && mass(s.quality_scrap_kg);
 const total = validScrap ? Number(s.production_scrap_kg)+Number(s.quality_scrap_kg) : null;
 const rawRate = validMass && validScrap && Number.isFinite(total) ? scrapRate(total,s.produced_kg) : null;
 const rate = Number.isFinite(rawRate) ? rawRate : null;
 const hasStandard = mass(s.running_standard_percent) && Number.isInteger(s.standard_revision) && s.standard_revision>0 &&
  (!s.startup_id || mass(s.startup_standard_kg) && Number.isInteger(s.startup_standard_revision) && s.startup_standard_revision>0);
 const startupComplete = s.startup_context_complete === true && (!s.startup_id ||
  mass(s.startup_kg) && mass(s.previous_startup_kg) && mass(s.cumulative_startup_kg) && Number(s.startup_kg)<=Number(s.production_scrap_kg));
 const contextComplete = !!s.product_id && !!s.line_id && startupComplete;
 const comparable = rate !== null && contextComplete && hasStandard && mass(s.startup_allowance_kg) &&
  mass(s.running_excess_kg) && typeof s.above_running_standard === 'boolean';
 const status = rate === null ? 'MISSING_DATA' : !hasStandard ? 'MISSING_STANDARD' : !comparable ? 'MISSING_DATA' : 'NORMAL';
 if (!comparable) return {status,high:false,rate,adjustedRate:null,standard:hasStandard?Number(s.running_standard_percent):null,expectedKg:null,excessKg:null,startupExcessKg:null,startupAllowanceKg:null};
 const assessment = abnormalScrap({total_scrap_kg:total,produced_kg:s.produced_kg,running_standard_percent:s.running_standard_percent,
  startup_events:s.startup_id?[{startup_id:s.startup_id,scrap_kg:s.startup_kg}]:[],
  startup_standard_kg:s.startup_id?Math.max(0,Number(s.startup_standard_kg)-Number(s.previous_startup_kg)):null});
 const startupExcessKg = s.startup_id ? Math.max(0,Number(s.cumulative_startup_kg)-Number(s.startup_standard_kg)) : 0;
 // SQL numeric decides the exact running boundary; JS rates are display values.
 const high = s.above_running_standard || !!s.startup_id && decimalCompare(s.cumulative_startup_kg,s.startup_standard_kg)===1;
 return {status:high?'HIGH':'NORMAL',high,rate,adjustedRate:assessment.running_rate,standard:Number(s.running_standard_percent),
  expectedKg:Number(s.produced_kg)*Number(s.running_standard_percent)/100+assessment.startup.expected_kg,
  excessKg:Number(s.running_excess_kg),startupExcessKg,startupAllowanceKg:assessment.startup.expected_kg};
}
