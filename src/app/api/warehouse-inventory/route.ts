import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient} from '@/services/authorization';
const headers={'Cache-Control':'private, no-store'};
const uuid=(s:string|null)=>!!s&&/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(s);
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory'),item=p.get('item'),mode=p.get('mode')||'context',page=Number(p.get('page')||1),item_type=p.get('item_type'),unit=p.get('unit')||null,kind=p.get('kind');
 if(!uuid(factory)||!uuid(item)||!['context','order'].includes(mode)||!Number.isSafeInteger(page)||page<1||page>1000000||[...p.keys()].some(k=>!['factory','item','item_type','unit','page','mode','kind'].includes(k))||unit&&unit.length>50||mode==='context'&&!['finished','material'].includes(item_type||'')||mode==='order'&&!['SALES','PRODUCTION'].includes(kind||''))throw {code:'22023'};
 const {db}=await authenticatedClient(),{data,error}=mode==='order'?await db.rpc('warehouse_reservation_order',{factory,target:item,kind}):await db.rpc('warehouse_inventory_context',{factory,item,item_type,unit,page});if(error)throw error;
 return NextResponse.json(data,{headers});
}catch(error){const e=error as {code?:string;message?:string};return NextResponse.json({error:e.message==='unauthorized'?'unauthorized':e.code==='42501'?'permissionError':'dataWarning'},{status:e.message==='unauthorized'?401:e.code==='42501'?403:400,headers});}}
