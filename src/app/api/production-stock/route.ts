import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(v);
const known=['material_invalid','material_quantity','material_changed','material_shortage','request_conflict','recording_shift_unavailable','material_reconciliation_reason','production_stock_disabled','production_stock_legacy_review','production_stock_shortage','production_stock_count_required','production_stock_count_changed','production_stock_investigation_required','production_stock_recipe_review','production_stock_schedule_required','material_unit_missing'];
function invalid():never{throw {code:'22023',message:'material_invalid'};}
function failure(error:unknown){const e=error as{code?:string;message?:string};return NextResponse.json({error:e.code==='42501'||e.message==='invalid_origin'?'permissionError':e.message==='unauthorized'?'signIn':known.includes(e.message||'')?e.message:'dataWarning'},
 {status:e.code==='42501'||e.message==='invalid_origin'?403:e.message==='unauthorized'?401:e.code==='40001'?409:e.code==='22023'||e.code==='23505'||e.code==='23503'?422:503,headers});}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),mode=p.get('mode')||'work',page=Number(p.get('page')||1),notes=Number(p.get('notes_page')||1),handover=Number(p.get('handover_page')||1);
 const material=p.get('material');
 if(!uuid(factory)||!['work','requests','reservations'].includes(mode)||mode==='reservations'&&!uuid(material)||mode!=='reservations'&&material!==null||![page,notes,handover].every(n=>Number.isSafeInteger(n)&&n>=1&&n<=10000)||[...p.keys()].some(k=>!['factory','mode','page','notes_page','handover_page','material'].includes(k)||p.getAll(k).length!==1))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc(mode==='reservations'?'production_stock_reservation_details':mode==='requests'?'production_stock_requests':'production_stock_work',mode==='reservations'?{factory,material,page}:mode==='requests'?{factory,page}:{factory,notes_page:notes,handover_page:handover});if(error)throw error;return NextResponse.json({data},{headers});
 }catch(e){return failure(e);}}
export async function POST(req:NextRequest){try{
 verifyOrigin(req);const raw=await req.text();if(raw.length>40000)invalid();let b;try{b=JSON.parse(raw);}catch{invalid();}
 if(!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).some(k=>!['factory','operation','payload','request_id'].includes(k))||!uuid(b.factory)||!uuid(b.request_id)||!['REQUEST','DELIVER','ADJUST','HANDOVER','NOTE','ACK','RESOLVE','ENABLE'].includes(b.operation)||!b.payload||typeof b.payload!=='object'||Array.isArray(b.payload))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc('production_stock_action',b);if(error)throw error;return NextResponse.json({data},{headers});
 }catch(e){return failure(e);}}
