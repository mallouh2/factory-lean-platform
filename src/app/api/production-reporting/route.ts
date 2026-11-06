import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize } from '@/services/authorization';
import { historyError } from '@/services/history-response';
import { readProductionReporting } from '@/services/production-reporting';
import { parseReportingQuery, reportingFetch } from '@/utils/production-reporting.mjs';

export async function GET(req: NextRequest) {
  try {
    const args = parseReportingQuery(req.nextUrl.searchParams);
    const context = await authenticatedClient(reportingFetch());
    await authorize(args.factory, 'orders', 'view', context);
    const data = await readProductionReporting(context.db, args);
    return NextResponse.json(data, { headers: { 'Cache-Control': 'private, no-store' } });
  } catch (error) {
    if (error && typeof error === 'object' && 'code' in error && error.code === '40001')
      return NextResponse.json({ error: 'reportingChanged', restart: true },
        { status: 409, headers: { 'Cache-Control': 'private, no-store' } });
    return historyError(error);
  }
}
