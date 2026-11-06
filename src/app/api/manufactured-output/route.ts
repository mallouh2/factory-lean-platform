import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
import {exactRecordingPayload,recordingFailure,recordingFetch} from '@/utils/production-recording-v3.mjs';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function failure(error:unknown){
 const e=error as {code?:string;message?:string};
 if(e?.message==='output_active_execution'&&e.code==='40001')return NextResponse.json({error:'compActiveRequired',reason:'output_active_execution',outcome:'REJECTED'},{status:409,headers});
 if(e?.message==='invalid_origin')return NextResponse.json({error:'permissionError',outcome:'REJECTED'},{status:403,headers});
 if(e?.code==='P0001'&&['planning_locked','planning_already_started','request_conflict'].includes(e.message||''))return NextResponse.json({error:'recordingContextChanged',reason:e.message,outcome:'REJECTED'},{status:409,headers});
 if(e?.code==='P0001'&&['output_revision','output_reinspection_required'].includes(e.message||''))return NextResponse.json({error:'recordingContextChanged',reason:e.message,outcome:'REJECTED'},{status:409,headers});
 if(e?.code==='P0001'&&/^output_[a-z_]+$/.test(e.message||''))return NextResponse.json({error:'recordingValidation',reason:e.message,outcome:'REJECTED'},{status:422,headers});
 const {status,...body}=recordingFailure(error);return NextResponse.json(body,{status,headers});
}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),mode=p.get('mode')||'list',target=p.get('target'),work=p.get('work'),page=Number(p.get('page')||0),after=p.get('after');
 if((after!==null&&(!uuid(after)||mode!=='planning'))||(mode==='planning'&&(target!==null||work!==null||p.has('page')))||!uuid(factory)||(target!==null&&!uuid(target))||(work!==null&&(!uuid(work)||mode!=='completion'||!target))||!Number.isSafeInteger(page)||page<0||page>100000||[...p.keys()].some(k=>!['factory','mode','target','work','page','after'].includes(k))||(mode==='order'&&!target))throw {code:'22023'};
 const {db}=await authenticatedClient(recordingFetch());
 if(mode==='compensation'&&!target)throw {code:'22023'};
 const {data,error}=mode==='planning'?await db.rpc('manufactured_planning_work_read',{factory,after_id:after}):mode==='compensation'?await db.rpc('production_compensation_read',{factory,target}):mode==='order'?await db.rpc('manufactured_output_order_read',{factory,target}):mode==='completion'?await db.rpc(target?'manufactured_completion_context':'manufactured_completion_read',{factory,page,...(target?{target,work_id:work}:{})}):mode==='receiving'?await db.rpc(target?'manufactured_receiving_context':'manufactured_receiving_read',{factory,page,...(target?{target}:{})}):await db.rpc('manufactured_output_read',{factory,mode,target,page});if(error)throw error;
 return NextResponse.json(data,{headers});
}catch(error){return failure(error)}}
export async function POST(req:NextRequest){try{
 const raw=await req.text();if(raw.length>100000)throw {code:'22023'};
 const body=JSON.parse(raw),args=body.args;
 if(['plan_production_compensation','plan_quality_production','plan_measurement_makeup'].includes(body.command))verifyOrigin(req);
 if(!args||!uuid(args.factory)||!uuid(args.request_id)||!args.payload||typeof args.payload!=='object'||Array.isArray(args.payload))throw {code:'22023'};
 const {db}=await authenticatedClient(recordingFetch());let name:string;
 if(body.command==='record_manufactured_output'){
  if(Object.keys(args).some(k=>!['factory','request_id','payload'].includes(k)))throw {code:'22023'};
  exactRecordingPayload(raw,args.payload);name='record_manufactured_output';
 }else if(body.command==='reconcile_manufactured_output'){
  if(!uuid(args.target)||!uuid(args.finding)||!Number.isSafeInteger(args.expected_revision)||args.expected_revision<1||Object.keys(args).some(k=>!['factory','request_id','payload','target','finding','expected_revision'].includes(k))||Object.keys(args.payload).some(k=>!['source_id','source_lot_id','source_location','identification_note','physical_confirmation','reason'].includes(k)))throw {code:'22023'};
  name=body.command;
 }else if(body.command==='revise_manufactured_completion'){
  if(!uuid(args.target)||!Number.isSafeInteger(args.expected_revision)||args.expected_revision<1||Object.keys(args).some(k=>!['factory','request_id','payload','target','expected_revision'].includes(k))||!['CANCEL','CHANGE'].includes(args.payload.action)||!args.payload.expected_state||typeof args.payload.expected_state!=='object'||Array.isArray(args.payload.expected_state))throw {code:'22023'};
  name=body.command;
 }else if(['receive_manufactured_output','plan_manufactured_completion','plan_production_compensation','plan_quality_production','plan_measurement_makeup'].includes(body.command)){
  if(typeof args.payload.quantity!=='string'||!uuid(args.target)||!Number.isSafeInteger(args.expected_revision)||args.expected_revision<1||Object.keys(args).some(k=>!['factory','request_id','payload','target','expected_revision'].includes(k)))throw {code:'22023'};
  if(body.command==='plan_measurement_makeup'&&(args.payload.recording_complete_confirmation!==true||Object.keys(args.payload).some(k=>!['quantity','recording_complete_confirmation'].includes(k))))throw {code:'22023'};
  name=body.command;
 }else if(body.command==='manufactured_output_command'){
  if(!['QUALITY','ACKNOWLEDGE'].includes(args.operation)||!uuid(args.target)||!Number.isSafeInteger(args.expected_revision)||args.expected_revision<1||Object.keys(args).some(k=>!['factory','request_id','payload','operation','target','expected_revision'].includes(k)))throw {code:'22023'};
  name='manufactured_output_command';
 }else throw {code:'22023'};
 const {data,error}=await db.rpc(name,args);if(error)throw error;
 return NextResponse.json({data},{headers});
}catch(error){return failure(error)}}
