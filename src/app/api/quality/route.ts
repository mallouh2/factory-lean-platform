import { NextRequest,NextResponse } from 'next/server';
import { authenticatedClient } from '@/services/authorization';
import { historyError,historyPage,historyUuid } from '@/services/history-response';
export async function GET(req:NextRequest){
 try {
  const {db}=await authenticatedClient(),params=req.nextUrl.searchParams;
  const factory=historyUuid(params.get('factory')),mode=params.get('mode')||'board';
  const page=historyPage(params.get('page'));
  for(const key of ['product','sales_line','entry','shift','line','rejection','material_request','selected'])if(params.get(key))historyUuid(params.get(key));
  const query:Record<string,unknown>=Object.fromEntries([...params].filter(([key,value])=>key!=='factory'&&value!==''));
  query.mode=mode;query.page=page;
  const result=mode==='sources'?await db.rpc('finished_source_stock',{factory,product:historyUuid(params.get('product')),unit:params.get('unit'),sales_line:params.get('sales_line')||null,entry:params.get('entry')||null,page,material_request:params.get('material_request')||null}):
   await db.rpc('quality_read',{factory,query});
  if(result.error)throw result.error;
  return NextResponse.json(result.data,{headers:{'Cache-Control':'private, no-store'}});
 }catch(cause){return historyError(cause);}
}
