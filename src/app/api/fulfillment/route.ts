import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
import { inventoryColumns, validInventoryFilters } from '@/utils/warehouse-inventory.mjs';

export async function GET(req: NextRequest) {
  try {
    const factory = req.nextUrl.searchParams.get('factory') || '';
    const mode = req.nextUrl.searchParams.get('mode') || 'sales';
    const page = Number(req.nextUrl.searchParams.get('page') || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000000) throw Error('invalid_input');
    const definitions = {
      sales: ['sales_orders', 'sales_orders_page'],
      identities: ['factory','order_identity_context'],
      warehouse: ['warehouse', 'warehouse_page'],
      inventory: ['warehouse', 'warehouse_inventory'],
      stored_wip: ['warehouse','warehouse_stored_unfinished'],
      production: ['orders', 'fulfillment_production_context'],
      slot: ['orders', 'sales_planning_slot'],
      guidance: ['orders', 'sales_planning_guidance'],
      movements: ['warehouse', 'warehouse_movements'],
      pool: ['warehouse','pooled_dispatch_context'],
      confirmation: ['sales_orders','sales_confirmation_preview'],
    } as const;
    if (!Object.hasOwn(definitions, mode)) throw Error('invalid_input');
    const [module, rpc] = definitions[mode as keyof typeof definitions];
    const context = await authenticatedClient();
    await authorize(factory, module, 'view', context);
    const filters = mode === 'inventory' ? JSON.parse(req.nextUrl.searchParams.get('filters') || '{}') : {};
    const sort = req.nextUrl.searchParams.get('sort') || 'name', direction = req.nextUrl.searchParams.get('direction') || 'asc';
    if (mode === 'inventory' && (!validInventoryFilters(filters) || !inventoryColumns.some(c => c[0] === sort) || !['asc','desc'].includes(direction))) throw Error('invalid_input');
    const args = mode === 'identities' ? {factory} : mode === 'pool'||mode==='confirmation' ? {factory,sales_order:req.nextUrl.searchParams.get('order')} : mode === 'inventory' ? { factory, page, filters, sort, direction } : mode === 'movements'
      ? { factory, item: req.nextUrl.searchParams.get('item'), item_type: req.nextUrl.searchParams.get('item_type'), page }
      : mode === 'production' || mode === 'slot' || mode === 'guidance'
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
