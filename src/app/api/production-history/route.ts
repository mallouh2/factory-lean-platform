import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
import { parseHistoryQuery } from '@/utils/production-history.mjs';
export async function GET(req: NextRequest) {
  try {
    const context=await authenticatedClient();
    const factory=req.nextUrl.searchParams.get('factory') || '';
    await authorize(factory,'orders','view',context);
    const values=req.nextUrl.searchParams.get('field');
    const args=values ? {factory,field:values,search:req.nextUrl.searchParams.get('search') || '',page:Number(req.nextUrl.searchParams.get('values_page') || 1)} : req.nextUrl.searchParams.get('options')==='1' ? {factory} : {factory,...parseHistoryQuery(req.nextUrl.searchParams)};
    const {data,error}=await context.db.rpc(values ? 'production_history_values' : req.nextUrl.searchParams.get('options')==='1' ? 'production_history_options' : 'production_history',args);
    if(error) throw error;
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return NextResponse.json(safeError(error),{status:403});}
}
