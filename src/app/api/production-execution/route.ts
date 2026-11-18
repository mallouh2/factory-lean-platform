import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(v);
const known=['execution_orders_changed','execution_orders_invalid','execution_plan_immutable','execution_order_interrupted','execution_reason_required','execution_context_changed','execution_command_conflict','execution_record_output_first','execution_end_transfer_first','execution_not_active','execution_no_remaining','execution_plan_required','execution_line_busy','execution_out_of_sequence','execution_machine_stopped','maintenance_active_stop','maintenance_capacity_reserved','maintenance_machine_not_ready','output_quality_hold','output_work_not_ready','production_material_not_ready'];
const aliases:Record<string,string>={production_material_not_ready:'psStartBlocked',planning_missing_rate:'planningMissingRate',planning_incompatible_line:'planningIncompatibleLine',planning_invalid_calendar:'planningInvalidCalendar',planning_invalid_quantity:'planningInvalidQuantity',execution_already_started:'executionAlreadyStarted',maintenance_active_stop:'maintenanceActiveStop',maintenance_capacity_reserved:'maintenanceCapacityReserved',maintenance_machine_not_ready:'maintenanceMachineNotReady',maintenance_execution_window_unknown:'maintenanceUnknownWindow',maintenance_configuration_unknown:'maintenanceConfigurationUnknown',output_quality_hold:'planningQualityHold',output_work_not_ready:'compNotReady',output_work_capability:'planningIncompatibleLine'};
for(const key of ['f20SourceChanged','f20DestinationLineRequired','f20DestinationBusy','f20DestinationUnavailable','f20DestinationPaused','f20FixedRoute','f20DependencyMismatch','f20SharedStockRequired','f20SourceWorkRequired','transferStopRequired','incompatible_alternative'])known.push(key);
known.push('material_route_missing','material_route_ambiguous','material_weight_missing','material_recipe_missing','material_unit_missing','material_configuration_invalid');
known.push('f48AlternativeStopConflict','f48UseReturn','f48ConfirmHandover','f48TransferChanged','f48RecoveryRequired','f48RecoveryChanged','f48LineUnavailable','f48DependencyStopped');
aliases.incompatible_alternative='incompatibleAlternative';
function invalid():never{throw {code:'22023',message:'execution_context_changed'};}
function failure(error:unknown,rejectedRequest?:string,receipt?:{intent:unknown;current:unknown}){const e=error as{code?:string;message?:string;details?:string},denied=e.code==='42501'||e.message==='invalid_origin';
 let materials:unknown;
 if(e.message==='production_material_not_ready'&&e.details){try{const detail=JSON.parse(e.details);materials={reason:typeof detail.reason==='string'?(aliases[detail.reason]||detail.reason):undefined,legacy:Array.isArray(detail.legacy)?detail.legacy.map((r:Record<string,unknown>)=>({name:r.name,name_ar:r.name_ar,held:r.held,unit:r.unit})):[],rows:Array.isArray(detail.rows)?detail.rows.map((r:Record<string,unknown>)=>({name:r.name,name_ar:r.name_ar,missing:r.missing,unit:r.unit})):[]};}catch{/* General error remains actionable if details are unavailable. */}}
 return NextResponse.json({error:denied?'permissionError':e.message==='unauthorized'?'signIn':aliases[e.message||'']||(known.includes(e.message||'')?e.message:'executionRejected'),materials,...(rejectedRequest?{outcome:'REJECTED',request_id:rejectedRequest}:{}),...receipt},{status:denied?403:e.message==='unauthorized'?401:e.code==='40001'?409:e.code==='22023'||known.includes(e.message||'')||aliases[e.message||'']?422:503,headers});}
export async function GET(req:NextRequest){try{const p=req.nextUrl.searchParams,factory=p.get('factory'),item=p.get('item');
 if(p.get('mode')==='return'){
  const work_center=p.get('work_center');if(!uuid(factory)||!uuid(work_center)||[...p.keys()].some(k=>!['factory','mode','work_center'].includes(k)||p.getAll(k).length!==1))invalid();
  const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_return_context',{factory,work_center});if(error)throw error;return NextResponse.json({data},{headers});
 }
 if(p.get('mode')==='line-transfer'){
  const source_machine=p.get('source_machine');if(!uuid(factory)||!uuid(item)||!uuid(source_machine)||[...p.keys()].some(k=>!['factory','item','mode','source_machine'].includes(k)||p.getAll(k).length!==1))invalid();
  const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_line_transfer_options',{factory,item,source_machine});if(error)throw error;return NextResponse.json({data},{headers});
 }
 if(p.get('mode')==='outcome'){
  const request_id=p.get('request_id');if(!uuid(factory)||!uuid(item)||!uuid(request_id)||[...p.keys()].some(k=>!['factory','item','mode','request_id'].includes(k)||p.getAll(k).length!==1))invalid();
  const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_execution_outcome',{factory,item,request_id});if(error)throw error;if(data?.outcome==='REJECTED')return failure(data.error,request_id!,{intent:data.intent,current:data.current});return NextResponse.json(data,{headers});
 }
 if(p.get('mode')==='orders'){
  if(!uuid(factory)||[...p.keys()].some(k=>!['factory','mode','cursor'].includes(k)||p.getAll(k).length!==1)||(p.get('cursor')||'').length>1000)invalid();
  let cursor=null;if(p.has('cursor')){try{cursor=JSON.parse(p.get('cursor')!);}catch{invalid();}}
  const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_execution_orders',{factory,cursor,page_size:100});if(error)throw error;return NextResponse.json({data},{headers});
 }
 if(!uuid(factory)||!uuid(item)||[...p.keys()].some(k=>!['factory','item'].includes(k)||p.getAll(k).length!==1))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_execution_context',{factory,item});if(error)throw error;return NextResponse.json({data},{headers});
 }catch(e){return failure(e);}}
export async function POST(req:NextRequest){try{verifyOrigin(req);const raw=await req.text();if(raw.length>4000)invalid();let b;try{b=JSON.parse(raw);}catch{invalid();}
 const returning=b?.operation==='RETURN_PRODUCTION',transfer=b?.operation==='TRANSFER_LINE'||returning,keys=['factory','item','operation','reason','fingerprint','request_id','output_confirmed',...(transfer?['source_machine','alternative_machine']:[]),...(returning?['transfer_id']:[])];
 if(!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).some(k=>!keys.includes(k))||keys.some(k=>!Object.hasOwn(b,k))||!uuid(b.factory)||!uuid(b.item)||!uuid(b.request_id)
 ||!['INTERRUPT','RESUME','START_SELECTED','TRANSFER_LINE','RETURN_PRODUCTION'].includes(b.operation)||transfer&&(!uuid(b.source_machine)||!uuid(b.alternative_machine))||returning&&!uuid(b.transfer_id)||typeof b.reason!=='string'||transfer&&b.reason.trim().length<3||b.reason.trim().length>0&&b.reason.trim().length<3||b.reason.length>240||typeof b.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(b.fingerprint)||typeof b.output_confirmed!=='boolean')invalid();
 const {db}=await authenticatedClient();const args={...b};if(transfer)delete args.operation;
 const {data,error}=await db.rpc(returning?'production_return_submit':transfer?'production_line_transfer_submit':'production_execution_submit',args);if(error)throw error;
 if(data?.request_id!==b.request_id)throw Error('executionOutcomeUnknown');
 if(data?.outcome==='REJECTED')return failure(data.error,b.request_id);
 if(data?.outcome!=='COMMITTED')throw Error('executionOutcomeUnknown');return NextResponse.json(data,{headers});
 }catch(e){return failure(e);}}
