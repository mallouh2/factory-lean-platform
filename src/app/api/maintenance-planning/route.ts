import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize } from '@/services/authorization';
import { historyError, historyPage, historyUuid } from '@/services/history-response';
import { collectMaintenancePages } from '@/utils/maintenance-planning-view.mjs';
import { maintenanceReaderArgs } from '@/utils/maintenance-planning-readers.mjs';
import { operationalBoardArgs } from '@/utils/planning-operational-board.mjs';
export async function GET(req: NextRequest) {
  try {
    const context = await authenticatedClient();
    if(req.nextUrl.searchParams.get('view')==='operational'){
      const args=operationalBoardArgs(req.nextUrl.searchParams);
      await authorize(args.factory,'factory','view',context);await authorize(args.factory,'maintenance','view',context);
      if(args.domain==='all')await authorize(args.factory,'orders','view',context);
      const {data,error}=await context.db.rpc('planning_operational_board',args);if(error)throw error;
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    if (req.nextUrl.searchParams.has('mode')) {
      const {mode,args}=maintenanceReaderArgs(req.nextUrl.searchParams);
      await authorize(args.factory,'maintenance','view',context);
      await authorize(args.factory,'factory','view',context);
      if(mode!=='history')await authorize(args.factory,'orders','view',context);
      const {data,error}=await context.db.rpc(`maintenance_planning_${mode}`,args);
      if(error)throw error;
      return NextResponse.json(data?.capacity==='INCOMPLETE'?{...data,error:'mpIncomplete'}:data,
        {status:data?.capacity==='INCOMPLETE'?503:200,headers:{'Cache-Control':'private, no-store'}});
    }
    const factory = historyUuid(req.nextUrl.searchParams.get('factory'));
    await authorize(factory,'maintenance','view',context);
    if (req.nextUrl.searchParams.get('view') === 'board') {
      const read = async (name: string, args: Record<string, unknown>) => {
        const { data, error } = await context.db.rpc(name,args);
        if (error) throw error;
        return data;
      };
      const schedules = await collectMaintenancePages((page: number) => read('maintenance_planning_read',{factory,page}),50);
      const requests = await collectMaintenancePages((page: number) => read('maintenance_page',{
        factory,filters:{status:'ALL'},page,selected:null,history_page:1,
      }),25);
      if (schedules.rows.some((s: { maintenance_request_id: string }) =>
        !requests.rows.some((r: { id: string }) => r.id === s.maintenance_request_id))) throw Error('maintenancePlanningIncomplete');
      return NextResponse.json({ active:schedules.active, schedules:schedules.rows, requests:requests.rows,
        read_at:new Date().toISOString(), preview_available:Boolean(schedules.preview_available), history_available:Boolean(schedules.history_available) },
      {headers:{'Cache-Control':'private, no-store'}});
    }
    const { data, error } = await context.db.rpc('maintenance_planning_read',{
      factory, page: historyPage(req.nextUrl.searchParams.get('page')),
    });
    if (error) throw error;
    return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
  } catch (error) {
    if(req.nextUrl.searchParams.get('view')==='operational'){
      const code=error&&typeof error==='object'&&'code' in error?String(error.code):null;
      const denied=code==='42501'||error instanceof Error&&error.message==='permission_denied';
      const unauthenticated=error instanceof Error&&error.message==='unauthorized';
      return NextResponse.json({completeness:'ERROR',error:unauthenticated?'unauthorized':denied?'permissionError':code==='40001'?'mpBoardChanged':code==='22023'?'maintenanceInvalid':code==='P0002'?'noResults':'mpBoardError'},
        {status:unauthenticated?401:denied?403:code==='40001'?409:code==='22023'?400:code==='P0002'?404:503,headers:{'Cache-Control':'private, no-store'}});
    }
    if (req.nextUrl.searchParams.has('mode') && error && typeof error==='object' && 'code' in error && String(error.code).startsWith('22'))
      return NextResponse.json({error:'maintenanceInvalid'},{status:400,headers:{'Cache-Control':'private, no-store'}});
    if (error && typeof error==='object' && 'code' in error && error.code==='40001')
      return NextResponse.json({error:'mpPreviewStale'},{status:409,headers:{'Cache-Control':'private, no-store'}});
    if (error instanceof Error && error.message === 'maintenancePlanningIncomplete')
      return NextResponse.json({error:error.message},{status:503,headers:{'Cache-Control':'private, no-store'}});
    return historyError(error);
  }
}
