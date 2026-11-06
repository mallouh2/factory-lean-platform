import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
import {recordingFetch,recordingFailure} from '@/utils/production-recording-v3.mjs';
import {exactHistoricalPayload} from '@/utils/historical-production.mjs';
const headers={'Cache-Control':'private, no-store'},uuid=(v:unknown)=>typeof v==='string'&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(v);
function failure(error:unknown){const {status,...body}=recordingFailure(error);return NextResponse.json(body,{status,headers});}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),day=p.get('day');
 if(!uuid(factory)||(day!==null&&!/^\d{4}-\d{2}-\d{2}$/.test(day))||[...p.keys()].some(k=>!['factory','day'].includes(k)))throw {code:'22023'};
 const {db}=await authenticatedClient(recordingFetch()),{data,error}=await db.rpc('historical_production_read',{factory,day});if(error)throw error;
 return NextResponse.json(data,{headers});
}catch(error){return failure(error)}}
export async function POST(req:NextRequest){try{
 verifyOrigin(req);const raw=await req.text();if(raw.length>60000)throw {code:'22023'};const body=JSON.parse(raw);
 if(Object.keys(body).some(k=>!['factory','operation','request_id','payload'].includes(k))||!uuid(body.factory)||!uuid(body.request_id)||!['SUBMIT','APPROVE','REJECT'].includes(body.operation)||!body.payload||typeof body.payload!=='object'||Array.isArray(body.payload))throw {code:'22023'};
 if(body.operation==='SUBMIT'){
  const p=body.payload.measurement;
  if(!p||typeof p!=='object'||Array.isArray(p))throw {code:'22023'};
  exactHistoricalPayload(raw,body);
 }
 const {db}=await authenticatedClient(recordingFetch()),{data,error}=await db.rpc('historical_production_command',body);if(error)throw error;
 return NextResponse.json({data},{headers});
}catch(error){return failure(error)}}
