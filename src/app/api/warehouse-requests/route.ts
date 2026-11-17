import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,authorize} from '@/services/authorization';
import {warehouseRequestsPage} from '@/services/warehouse-requests';
import {historyFetch} from '@/utils/production-history.mjs';
const headers={'Cache-Control':'private, no-store'};
export async function GET(req:NextRequest){try{
 const p=req.nextUrl.searchParams,factory=p.get('factory')||'',page=Number(p.get('page')||1),kind=p.get('kind')||'',search=p.get('search')||'',language=p.get('language')||'en',status=p.get('status')||'active';
 if(!/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(factory)||!Number.isSafeInteger(page)||page<1||page>1000000||search.length>200||!['','issue','unfinished','receipt','acknowledge','dispatch','raw-return','production-stock'].includes(kind)||!['active','completed','all'].includes(status)||!['en','ar'].includes(language)||[...p.keys()].some(k=>!['factory','page','kind','search','language','status'].includes(k)||p.getAll(k).length!==1))throw {code:'22023'};
 const context=await authenticatedClient(historyFetch());await authorize(factory,'warehouse','view',context);
 const data=await warehouseRequestsPage(context.db,factory,{page,kind,search,language:language as 'en'|'ar',status:status as 'active'|'completed'|'all'},req.signal);
 await authorize(factory,'warehouse','view',context);return NextResponse.json(data,{headers});
}catch(error){return NextResponse.json({error:'dataWarning'},{status:(error as Error)?.message==='unauthorized'?401:(error as Error)?.message==='permission_denied'||(error as {code?:string})?.code==='42501'?403:400,headers});}}
