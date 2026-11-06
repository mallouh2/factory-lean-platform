import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,authorize} from '@/services/authorization';
import {historyError} from '@/services/history-response';
import {parseShiftWorkQuery,shiftWorkResponse} from '@/utils/production-shift-work.mjs';

export async function GET(req:NextRequest) {
  try {
    const args=parseShiftWorkQuery(req.nextUrl.searchParams);
    const context=await authenticatedClient();
    await authorize(args.factory,'orders','view',context);
    const {data,error}=await context.db.rpc('production_shift_work',args);
    if(error) throw error;
    return NextResponse.json(shiftWorkResponse(data),{headers:{'Cache-Control':'private, no-store'}});
  }catch(error) {
    if(error && typeof error==='object' && 'code' in error && error.code==='40001')
      return NextResponse.json({error:'shiftWorkChanged',restart:true},{status:409,headers:{'Cache-Control':'private, no-store'}});
    return historyError(error);
  }
}
