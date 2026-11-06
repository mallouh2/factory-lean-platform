import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient} from '@/services/authorization';
import {historyError,historyUuid} from '@/services/history-response';

export async function GET(req:NextRequest) {
  try {
    const {db}=await authenticatedClient();
    const {data,error}=await db.rpc('production_start_readiness',{
      factory:historyUuid(req.nextUrl.searchParams.get('factory')),
      item:historyUuid(req.nextUrl.searchParams.get('item')),
    });
    if(error) throw error;
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error){return historyError(error);}
}
