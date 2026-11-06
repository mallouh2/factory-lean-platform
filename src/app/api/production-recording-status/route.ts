import {NextRequest,NextResponse} from 'next/server';
import {authenticatedClient,authorize} from '@/services/authorization';
import {parseRecordingStatusQuery,recordingFailure,recordingFetch} from '@/utils/production-recording-v3.mjs';

export async function GET(req:NextRequest) {
  try {
    const args=parseRecordingStatusQuery(req.nextUrl.searchParams);
    const context=await authenticatedClient(recordingFetch());
    await authorize(args.factory,'orders','view',context);
    await authorize(args.factory,'orders','edit',context);
    const {data,error}=await context.db.rpc('production_recording_request_status',args);
    if(error) throw error;
    if(!data || data.contract_version!==3 || !['COMMITTED','UNKNOWN'].includes(data.outcome)) throw new Error('invalid_contract');
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  }catch(error) {
    const {status,...body}=recordingFailure(error);
    return NextResponse.json(body,{status,headers:{'Cache-Control':'private, no-store'}});
  }
}
