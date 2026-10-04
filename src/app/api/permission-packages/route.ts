import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient } from '@/services/authorization';
import { historyError, historyUuid } from '@/services/history-response';
export async function GET(req: NextRequest) {
  try {
    const { db } = await authenticatedClient(), params = req.nextUrl.searchParams;
    const { data, error } = await db.rpc('permission_package_page', {
      factory: historyUuid(params.get('factory')),
      person: params.has('person') ? historyUuid(params.get('person')) : null,
    });
    if (error) throw error;
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) { return historyError(error); }
}
