import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, verifyOrigin } from '@/services/authorization';
import { historyError, historyUuid } from '@/services/history-response';
import { collectFactoryExport, exportViewModules, factoryWorkbook } from '@/utils/factory-export.mjs';

export const runtime = 'nodejs';
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    const body = await req.json();
    const factory = historyUuid(body.factory);
    const context = await authenticatedClient();
    await authorize(factory, 'factory', 'export', context);
    for (const module of exportViewModules) await authorize(factory, module, 'view', context);
    const startedAt = new Date().toISOString();
    const sheets = await collectFactoryExport(context.db, factory, startedAt);
    const factoryRow = sheets.find(sheet => sheet.sheet === 'Factory')?.rows[0];
    if (!factoryRow || factoryRow.id !== factory) throw { code: '42501' };
    // Recheck export authority before delivering the file; a title or View As never authorizes it.
    await authorize(factory, 'factory', 'export', context);
    const buffer = await factoryWorkbook({ factory: factoryRow, user: context.user,
      startedAt, completedAt: new Date().toISOString(), sheets, language: body.language === 'ar' ? 'ar' : 'en' });
    return new NextResponse(new Uint8Array(buffer), { headers: {
      'Content-Type': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'Content-Disposition': `attachment; filename="factory-data-${startedAt.slice(0,10)}.xlsx"`,
      'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff',
    } });
  } catch (error) {
    if (error instanceof Error && error.message.startsWith('export_')) return NextResponse.json(
      { error: error.message === 'export_too_large' || error.message === 'export_cell_too_long' ? 'factoryExportTooLarge' : 'factoryExportChanged' },
      { status: 409, headers: { 'Cache-Control': 'private, no-store' } });
    return historyError(error);
  }
}
