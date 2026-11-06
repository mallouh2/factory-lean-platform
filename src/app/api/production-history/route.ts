import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
import { parseHistoryQuery, historyFetch } from '@/utils/production-history.mjs';
import { readProductionHistory } from '@/services/production-history';
export async function GET(req: NextRequest) {
  try {
    const context=await authenticatedClient(historyFetch());
    const factory=req.nextUrl.searchParams.get('factory') || '';
    await authorize(factory,'orders','view',context);
    const entry=req.nextUrl.searchParams.get('scrap_total_entry');
    if(entry!==null){
      if(!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(entry))throw Error('invalid_entry');
      const {data,error}=await context.db.rpc('production_history_product_scrap',{factory,entry});
      if(error)throw error;
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    const values=req.nextUrl.searchParams.get('field');
    const args=values ? {factory,field:values,search:req.nextUrl.searchParams.get('search') || '',page:Number(req.nextUrl.searchParams.get('values_page') || 1)} : req.nextUrl.searchParams.get('options')==='1' ? {factory} : {factory,...parseHistoryQuery(req.nextUrl.searchParams)};
    if(!values&&req.nextUrl.searchParams.get('options')!=='1') {
      const data=await readProductionHistory(context.db,factory,args);
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    const {data,error}=await context.db.rpc(values ? 'production_history_values' : 'production_history_options',args);
    if(error) throw error;
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return NextResponse.json(safeError(error),{status:403});}
}
