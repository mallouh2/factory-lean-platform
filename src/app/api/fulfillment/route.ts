import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';

export async function GET(req: NextRequest) {
  try {
    const factory = req.nextUrl.searchParams.get('factory') || '';
    const mode = req.nextUrl.searchParams.get('mode') || 'sales';
    const page = Number(req.nextUrl.searchParams.get('page') || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000000) throw Error('invalid_input');
    const definitions = {
      sales: ['sales_orders', 'sales_orders_page'],
      warehouse: ['warehouse', 'warehouse_page'],
      production: ['orders', 'fulfillment_production_context'],
      slot: ['orders', 'sales_planning_slot'],
    } as const;
    if (!Object.hasOwn(definitions, mode)) throw Error('invalid_input');
    const [module, rpc] = definitions[mode as keyof typeof definitions];
    const context = await authenticatedClient();
    await authorize(factory, module, 'view', context);
    const args = mode === 'production' || mode === 'slot'
      ? { factory, item: req.nextUrl.searchParams.get('item') || null }
      : { factory, page };
    const { data, error } = await context.db.rpc(rpc, args);
    if (error) throw error;
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) {
    const result = safeError(error);
    return NextResponse.json(result.error === 'error' ? { error: 'dataWarning' } : result,
      { status: result.error === 'unauthorized' ? 401 : result.error === 'permissionError' ? 403 : 400 });
  }
}
