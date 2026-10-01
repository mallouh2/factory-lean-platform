import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
import { parseHistoryQuery } from '@/utils/production-history.mjs';
export async function GET(req: NextRequest) {
  try {
    const context=await authenticatedClient();
    const factory=req.nextUrl.searchParams.get('factory') || '';
    await authorize(factory,'orders','view',context);
    const args=req.nextUrl.searchParams.get('options')==='1' ? {factory} : {factory,...parseHistoryQuery(req.nextUrl.searchParams)};
    const {data,error}=await context.db.rpc(req.nextUrl.searchParams.get('options')==='1' ? 'production_history_options' : 'production_history',args);
    if(error) throw error;
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return NextResponse.json(safeError(error),{status:403});}
}
