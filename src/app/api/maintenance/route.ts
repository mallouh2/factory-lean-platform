import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient } from '@/services/authorization';
import { historyError, historyPage, historyUuid } from '@/services/history-response';
import { maintenanceFilterKeys } from '@/utils/maintenance.mjs';

export async function GET(req: NextRequest) {
  try {
    const { db } = await authenticatedClient();
    const params = req.nextUrl.searchParams;
    const factory = historyUuid(params.get('factory'));
    const machine = params.get('context_machine');
    if (params.has('start_context')) {
      const {data,error} = await db.rpc('maintenance_start_context',{
        factory,maintenance_request:historyUuid(params.get('start_context')),
      });
      if (error) throw error;
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    if (params.has('actual_stop_machine') || params.has('actual_stop_request')) {
      if (params.has('actual_stop_machine') && params.has('actual_stop_request')) throw {code:'22023'};
      const {data,error} = await db.rpc('maintenance_stop_context',{factory,
        machine:params.has('actual_stop_machine')?historyUuid(params.get('actual_stop_machine')):null,
        maintenance_request:params.has('actual_stop_request')?historyUuid(params.get('actual_stop_request')):null,
        history_page:historyPage(params.get('history_page'))});
      if(error) throw error;
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    if (params.has('downtime')) {
      const {data,error} = await db.rpc('maintenance_downtime_context',{factory,event:historyUuid(params.get('downtime'))});
      if(error) throw error;
      return NextResponse.json(data,{headers:{'Cache-Control':'private, no-store'}});
    }
    const filters = Object.fromEntries(maintenanceFilterKeys.filter((key: string) => params.has(key))
      .map((key: string) => [key, params.get(key)]));
    const { data, error } = await db.rpc(machine ? 'maintenance_machine_context' : 'maintenance_page', machine
      ? { factory, machine: historyUuid(machine) }
      : { factory, filters, page: historyPage(params.get('page')), selected: params.has('selected') ? historyUuid(params.get('selected')) : null,
        history_page: historyPage(params.get('history_page')) });
    if (error) throw error;
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) { return historyError(error); }
}
