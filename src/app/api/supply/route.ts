import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize } from '@/services/authorization';
import { historyError, historyPage, historyUuid } from '@/services/history-response';
import { validSupplyFilters } from '@/utils/supply-contract.mjs';

export async function GET(req: NextRequest) {
  try {
    const context = await authenticatedClient();
    const params = req.nextUrl.searchParams, factory = historyUuid(params.get('factory'));
    await authorize(factory, 'factory', 'view', context);
    const mode = params.get('mode') || 'mine';
    if (!['purchases', 'mine', 'stock_purchases', 'suppliers', 'materials', 'catalogue', 'lots', 'outputs', 'formulas', 'requirements'].includes(mode)) throw { code: '22023' };
    let filters;try { filters=JSON.parse(params.get('filters') || '{}'); } catch { throw { code:'22023' }; }
    if (!validSupplyFilters(filters)) throw { code: '22023' };
    const selected = params.has('selected') ? historyUuid(params.get('selected')) : null;
    const quantity = Number(params.get('quantity'));
    if (mode === 'requirements' && (!selected || !Number.isFinite(quantity) || quantity <= 0 || !params.get('unit'))) throw { code: '22023' };
    const { data, error } = await context.db.rpc(mode === 'requirements' ? 'product_requirements' : 'supply_page', mode === 'requirements'
      ? { factory, product: selected, quantity, unit: params.get('unit') }
      : { factory, mode, page: historyPage(params.get('page')), filters, selected });
    if (error) throw error;
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) { return historyError(error); }
}
