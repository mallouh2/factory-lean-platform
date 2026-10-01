import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, safeError } from '@/services/authorization';
export async function GET(req: NextRequest) {
  try {
    const context = await authenticatedClient();
    const factory = req.nextUrl.searchParams.get('factory') || '';
    await authorize(factory, 'orders', 'view', context);
    const page = Number(req.nextUrl.searchParams.get('page') || 1);
    if (!Number.isSafeInteger(page) || page < 1 || page > 1000000) throw Error('invalid_input');
    const { data, error } = await context.db.rpc('unfinished_inventory', {
      factory, lot_id:req.nextUrl.searchParams.get('lot') || null, include_consumed: req.nextUrl.searchParams.get('history') === '1', page,
    });
    if (error) throw error;
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) {
    return NextResponse.json(safeError(error), { status: 403 });
  }
}
