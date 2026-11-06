import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,authorize} from '@/services/authorization';
import {historyError} from '@/services/history-response';
import {completionQuery,completionFetch,completionSummary} from '@/utils/production-completion.mjs';

// Read-only protected progress with original measurement and current Quality result.
export async function GET(req:NextRequest){
 try{
  const {factory,item}=completionQuery(req.nextUrl.searchParams),context=await authenticatedClient(completionFetch());
  await authorize(factory,'orders','view',context);
  const {data,error}=await context.db.rpc('production_recording_progress',{factory,item});
  if(error)throw error;
  return NextResponse.json({...completionSummary(data,factory,item),request_type:data.request_type},{headers:{'Cache-Control':'private, no-store'}});
 }catch(error){return historyError(error);}
}
