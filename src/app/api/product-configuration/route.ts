import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,verifyOrigin} from '@/services/authorization';
import {validProductConfiguration} from '@/utils/product-configuration.mjs';
const uuid=(s:unknown)=>typeof s==='string'&&/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(s);
const headers={'Cache-Control':'private, no-store'};
function failure(e:unknown){
 const x=e as {message?:string;code?:string},denied=x.code==='42501'||x.message==='invalid_origin';
 const known=['unauthorized','not_found','permissionError','fulfillment_stock_identity','pipe_identity_immutable','pipe_capability_inherited','material_configuration_invalid','material_recipe_missing','planningInvalidSetup','invalid_capabilities'];
 // A PostgreSQL error proves its transaction failed; an RPC transport error does not.
 const definite=denied||x.message?.startsWith('f45')||x.message==='supply_state'||known.includes(x.message||'')||/^[0-9A-Z]{5}$/.test(x.code||'');
 const key=!definite?'f45SaveUnknown':x.message?.startsWith('f45')?x.message:x.message==='supply_state'?'f45UnitIdentity':x.code==='23505'?'f45CodeUsed':known.includes(x.message||'')?x.message:denied?'permissionError':'f45Invalid';
 return NextResponse.json({error:key},{status:!definite?503:denied?403:x.message==='unauthorized'?401:x.code==='40001'?409:422,headers});
}
export async function GET(req:NextRequest){try{const q=req.nextUrl.searchParams,factory=q.get('factory'),product=q.get('product'),request_id=q.get('request_id');if(!uuid(factory)||product!==null&&!uuid(product)||request_id!==null&&!uuid(request_id)||product&&request_id||[...q.keys()].some(k=>!['factory','product','request_id'].includes(k)||q.getAll(k).length!==1))throw Error('f45Invalid');const {db}=await authenticatedClient();const {data,error}=await db.rpc('product_configuration_context',{factory,product,request_id});if(error)throw error;return NextResponse.json(data,{headers});}catch(e){return failure(e);}}
export async function POST(req:NextRequest){try{verifyOrigin(req);const args=await req.json();if(!validProductConfiguration(args))throw Error('f45Invalid');const {db}=await authenticatedClient();const {data,error}=await db.rpc('save_product_configuration',args);if(error)throw error;return NextResponse.json({id:data},{headers});}catch(e){return failure(e);}}
