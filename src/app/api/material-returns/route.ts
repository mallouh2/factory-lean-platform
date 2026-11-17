import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(v);
const known=['material_invalid','material_quantity','material_return_scope','material_return_unavailable','material_return_closed','material_return_reason','material_changed','request_conflict'];
function invalid():never{throw {code:'22023',message:'material_invalid'};}
function failure(error:unknown){const e=error as{code?:string;message?:string};return NextResponse.json({error:e.code==='42501'||e.message==='invalid_origin'?'permissionError':e.message==='unauthorized'?'signIn':known.includes(e.message||'')?e.message:'dataWarning'},{status:e.code==='42501'||e.message==='invalid_origin'?403:e.message==='unauthorized'?401:e.code==='40001'?409:e.code==='22023'?422:503,headers});}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),mode=p.get('mode')||'work',audience=p.get('audience')||'PRODUCTION',page=Number(p.get('page')||1),request=p.get('request');
 if(!uuid(factory)||!['context','work'].includes(mode)||!['PRODUCTION','WAREHOUSE'].includes(audience)||!Number.isSafeInteger(page)||page<1||page>200||request!==null&&!uuid(request)||[...p.keys()].some(k=>!['factory','mode','audience','page','request'].includes(k)||p.getAll(k).length!==1))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc(mode==='context'?'material_return_context':'material_return_work',mode==='context'?{factory}:{factory,audience,page,request});if(error)throw error;return NextResponse.json({data},{headers});
}catch(e){return failure(e);}}
export async function POST(req:NextRequest){try{
 verifyOrigin(req);const raw=await req.text();if(raw.length>10000)invalid();let b;try{b=JSON.parse(raw);}catch{invalid();}
 if(!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).some(k=>!['factory','operation','payload','request_id'].includes(k))||!uuid(b.factory)||!uuid(b.request_id)||!['CREATE','RECEIVE','CANCEL'].includes(b.operation)||!b.payload||typeof b.payload!=='object'||Array.isArray(b.payload))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc('material_return_action',b);if(error)throw error;return NextResponse.json({data},{headers});
}catch(e){return failure(e);}}
