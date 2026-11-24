import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
const headers={'Cache-Control':'private, no-store'};
const uuid=(v:unknown)=>typeof v==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(v);
const handoverActions=['HANDOVER_SUBMIT','HANDOVER_RECEIVE'];
const known=['material_invalid','material_quantity','material_changed','material_shortage','request_conflict','recording_shift_unavailable','material_reconciliation_reason','production_stock_disabled','production_stock_legacy_review','production_stock_shortage','production_stock_count_required','production_stock_count_changed','production_stock_investigation_required','production_stock_recipe_review','production_stock_schedule_required','material_unit_missing','handover_shift_changed','handover_goods_changed','handover_already_submitted','handover_already_received','handover_requires_incoming','handoverMaintenanceMismatch'];
function invalid():never{throw {code:'22023',message:'material_invalid'};}
type Client=Awaited<ReturnType<typeof authenticatedClient>>['db'];
async function maintenanceChoices(db:Client,factory:string,target:{line?:string;machine?:string},request?:string){
 const access=await db.rpc('can_access',{factory,module:'maintenance',action:'view'});
 if(access.error)throw access.error;
 if(!access.data)throw {code:'42501'};
 const requests=()=>db.from('maintenance_requests').select('id,code,title,line_id,work_center_id,status').eq('factory_id',factory);
 let centers:string[]=[];
 if(target.line){
  const scope=await db.from('work_centers').select('id').eq('factory_id',factory).eq('line_id',target.line);
  if(scope.error)throw scope.error;
  centers=(scope.data||[]).map(row=>row.id);
 }
 const reads=request?[requests().eq('id',request)]:target.machine?[requests().eq('work_center_id',target.machine)]:
  [requests().eq('line_id',target.line),...(centers.length?[requests().in('work_center_id',centers)]:[])];
 const results=await Promise.all(reads);
 const eligible=results.flatMap(({data,error})=>{
  if(error)throw error;
  return (data||[]).filter(row=>['OPEN','ASSIGNED','IN_PROGRESS','COMPLETED'].includes(row.status)&&
   (target.machine?row.work_center_id===target.machine:row.line_id===target.line||centers.includes(row.work_center_id)));
 });
 return [...new Map(eligible.map(row=>[row.id,{id:row.id,label:[row.code,row.title].filter(Boolean).join(' · ')}])).values()];
}
function failure(error:unknown){const e=error as{code?:string;message?:string};return NextResponse.json({error:e.code==='42501'||e.message==='invalid_origin'?'permissionError':e.message==='unauthorized'?'signIn':known.includes(e.message||'')?e.message:'dataWarning'},
 {status:e.code==='42501'||e.message==='invalid_origin'?403:e.message==='unauthorized'?401:e.code==='40001'?409:e.code==='22023'||e.code==='23505'||e.code==='23503'?422:503,headers});}
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),mode=p.get('mode')||'work',page=Number(p.get('page')||1),notes=Number(p.get('notes_page')||1),handover=Number(p.get('handover_page')||1);
 if(mode==='handover-maintenance'){
  const line=p.get('line'),machine=p.get('machine');
  if(!factory||!uuid(factory)||(line===null)===(machine===null)||!uuid(line??machine)||
   [...p.keys()].some(k=>!['factory','mode','line','machine'].includes(k)||p.getAll(k).length!==1))invalid();
  const {db}=await authenticatedClient();
  return NextResponse.json({data:await maintenanceChoices(db,factory,{line:line??undefined,machine:machine??undefined})},{headers});
 }
 if(mode==='handover'||mode==='handover-orders'){
  const target=p.get('target'),search=p.get('search')||'';
  if(!uuid(factory)||target!==null&&!uuid(target)||!Number.isSafeInteger(page)||page<1||page>10000||
    search.length>100||[...p.keys()].some(k=>!(mode==='handover'?['mode','factory','target','page']:['mode','factory','target','search']).includes(k)||p.getAll(k).length!==1))invalid();
  const {db}=await authenticatedClient();
  const {data,error}=mode==='handover'?await db.rpc('production_handover_read',{factory,target,history_page:page})
    :await db.rpc('production_handover_orders',{factory,search,selected:target});
  if(error)throw error;return NextResponse.json({data},{headers});
 }
 const material=p.get('material');
 if(!uuid(factory)||!['work','requests','reservations'].includes(mode)||mode==='reservations'&&!uuid(material)||mode!=='reservations'&&material!==null||![page,notes,handover].every(n=>Number.isSafeInteger(n)&&n>=1&&n<=10000)||[...p.keys()].some(k=>!['factory','mode','page','notes_page','handover_page','material'].includes(k)||p.getAll(k).length!==1))invalid();
 const {db}=await authenticatedClient(),{data,error}=await db.rpc(mode==='reservations'?'production_stock_reservation_details':mode==='requests'?'production_stock_requests':'production_stock_work',mode==='reservations'?{factory,material,page}:mode==='requests'?{factory,page}:{factory,notes_page:notes,handover_page:handover});if(error)throw error;return NextResponse.json({data},{headers});
 }catch(e){return failure(e);}}
export async function POST(req:NextRequest){try{
 verifyOrigin(req);const raw=await req.text();if(raw.length>125000)invalid();let b;try{b=JSON.parse(raw);}catch{invalid();}
 if(!b||typeof b!=='object'||Array.isArray(b)||Object.keys(b).some(k=>!['factory','operation','payload','request_id'].includes(k))||!uuid(b.factory)||!uuid(b.request_id)||!['REQUEST','DELIVER','ADJUST','HANDOVER','NOTE','ACK','RESOLVE','ENABLE',...handoverActions].includes(b.operation)||!b.payload||typeof b.payload!=='object'||Array.isArray(b.payload))invalid();
 const exchange=handoverActions.includes(b.operation);
 if(!exchange&&raw.length>40000||b.operation==='HANDOVER_RECEIVE'&&!uuid(b.payload.handover_id))invalid();
 const {db}=await authenticatedClient();
 if(b.operation==='NOTE'&&b.payload.maintenance){
  const {maintenance,line,machine,item}=b.payload;
  if(!uuid(maintenance)||Boolean(line)===Boolean(machine)||!uuid(line||machine)||item||
   !(await maintenanceChoices(db,b.factory,{line,machine},maintenance)).length)
   throw {code:'22023',message:'handoverMaintenanceMismatch'};
 }
 const {data,error}=await db.rpc(exchange?'production_handover_action':'production_stock_action',b);if(error)throw error;return NextResponse.json({data},{headers});
 }catch(e){return failure(e);}}
