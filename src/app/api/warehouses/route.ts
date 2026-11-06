import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
import {recordingFailure,recordingFetch} from '@/utils/production-recording-v3.mjs';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v);
function failure(error:unknown){
 const e=error as {code?:string;message?:string};
 if(e.message==='invalid_origin')return NextResponse.json({error:'permissionError',outcome:'REJECTED'},{status:403,headers});
 if(e.code==='P0001'&&e.message?.startsWith('warehouse_'))return NextResponse.json({error:e.message,outcome:'REJECTED'},{status:e.message==='warehouse_revision'?409:422,headers});
 const {status,...body}=recordingFailure(error);return NextResponse.json(body,{status,headers});
}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory');if(!uuid(factory)||[...p.keys()].some(k=>k!=='factory'))throw {code:'22023'};
 const {db}=await authenticatedClient(recordingFetch()),{data,error}=await db.rpc('factory_warehouses_read',{factory});if(error)throw error;
 return NextResponse.json(data,{headers});
}catch(error){return failure(error)}}
export async function POST(req:NextRequest){try{
 verifyOrigin(req);const raw=await req.text();if(raw.length>6000)throw {code:'22023'};const a=JSON.parse(raw);
 if(a?.operation==='RECEIVE_STOCK'){
  if(!uuid(a.factory)||!uuid(a.request_id)||!a.payload||typeof a.payload!=='object'||Array.isArray(a.payload)||Object.keys(a).some(k=>!['factory','request_id','operation','payload'].includes(k)))throw {code:'22023'};
  const {db}=await authenticatedClient(recordingFetch()),{data,error}=await db.rpc('receive_warehouse_stock_at',{factory:a.factory,payload:a.payload,request_id:a.request_id});if(error)throw error;
  return NextResponse.json({data},{headers});
 }
 if(!a||!uuid(a.factory)||!uuid(a.request_id)||!['CREATE','UPDATE','DEFAULTS'].includes(a.operation)||(a.target!==null&&!uuid(a.target))||(a.expected_revision!==null&&(!Number.isSafeInteger(a.expected_revision)||a.expected_revision<1))||!a.payload||typeof a.payload!=='object'||Array.isArray(a.payload)||Object.keys(a).some(k=>!['factory','operation','target','payload','expected_revision','request_id'].includes(k)))throw {code:'22023'};
 const {db}=await authenticatedClient(recordingFetch()),{data,error}=await db.rpc('factory_warehouse_command',a);if(error)throw error;
 return NextResponse.json({data},{headers});
}catch(error){return failure(error)}}
