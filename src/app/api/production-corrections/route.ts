import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,authorize,verifyOrigin} from '@/services/authorization';
import {correctionCommand,correctionQuery,correctionResponse,correctionFailure} from '@/utils/production-corrections.mjs';
const headers={'Cache-Control':'private, no-store'};
export async function GET(req:NextRequest){
 try{
  if(req.nextUrl.searchParams.has('pending_count')){
   const params=req.nextUrl.searchParams;
   if(params.get('pending_count')!=='1'||[...params.keys()].some(k=>!['factory','pending_count'].includes(k)||params.getAll(k).length!==1))throw {code:'22023'};
   const args=correctionQuery(new URLSearchParams({factory:params.get('factory')||'',status:'PENDING',page_size:'1'}));
   const context=await authenticatedClient();
   await authorize(args.factory,'orders','view',context);
   await authorize(args.factory,'orders','approve',context);
   const {data,error}=await context.db.rpc('production_correction_read',{factory:args.factory,query:JSON.stringify(args.query)},{get:true});
   if(error)throw error;
   const result=correctionResponse(data,args,true);
   return NextResponse.json({total:result.total},{headers});
  }
  if(req.nextUrl.searchParams.has('context_entry')){
   const params=req.nextUrl.searchParams;
   if([...params.keys()].some(k=>!['factory','context_entry'].includes(k)||params.getAll(k).length!==1))throw {code:'22023'};
   const args=correctionQuery(new URLSearchParams({factory:params.get('factory')||'',entry:params.get('context_entry')||''}));
   const context=await authenticatedClient();await authorize(args.factory,'orders','view',context);
   const {data,error}=await context.db.rpc('production_correction_context',{factory:args.factory,entry:params.get('context_entry')},{get:true});
   if(error)throw error;
   return NextResponse.json(data,{headers});
  }
  const args=correctionQuery(req.nextUrl.searchParams),context=await authenticatedClient();
  await authorize(args.factory,'orders','view',context);
  const {data,error}=await context.db.rpc('production_correction_read',{factory:args.factory,query:JSON.stringify(args.query)},{get:true});
  if(error)throw error;
  const result=correctionResponse(data,args,true);
  if(result.rows.length){
   const ids=(key:string)=>[...new Set(result.rows.map((row:{current_values:Record<string,string>})=>row.current_values[key]))];
   const lookups=await Promise.all([
    context.db.from('production_orders').select('id,code').eq('factory_id',args.factory).in('id',ids('item_id')),
    context.db.from('production_requests').select('id,code').eq('factory_id',args.factory).in('id',ids('request_id')),
    context.db.from('products').select('id,name,name_ar').eq('factory_id',args.factory).in('id',ids('product_id')),
   ]);
   for(const lookup of lookups)if(lookup.error)throw lookup.error;
   result.metadata={items:lookups[0].data,requests:lookups[1].data,products:lookups[2].data};
  }
  return NextResponse.json(result,{headers});
 }catch(error){const result=correctionFailure(error);return NextResponse.json(result.body,{status:result.status===422?400:result.status,headers});}
}
export async function POST(req:NextRequest){
 try{
  verifyOrigin(req);
  if(Number(req.headers.get('content-length')??0)>100000)throw {code:'22023'};
  const text=await req.text();if(text.length>100000)throw {code:'22023'};
  let body;try{body=JSON.parse(text);}catch{throw {code:'22023'};}
  const args=correctionCommand(body),context=await authenticatedClient();
  await authorize(args.factory,'orders','view',context);
  if(args.operation!=='submit')await authorize(args.factory,'orders','approve',context);
  // Submit's edit OR approve authority and live factory scope are also checked
  // by SQL, together with every transition and the existing posting pipeline.
  const {data,error}=await context.db.rpc('production_correction_command',args);
  if(error)throw error;
  return NextResponse.json(correctionResponse(data,args),{headers});
 }catch(error){const result=correctionFailure(error,true);return NextResponse.json(result.body,{status:result.status,headers});}
}
