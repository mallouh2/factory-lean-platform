import { NextRequest, NextResponse } from 'next/server';
import { authenticatedClient, authorize, verifyOrigin } from '@/services/authorization';
import { historyError } from '@/services/history-response';
import { exportRequest, qualityReport } from '@/services/table-export';
import { collectTableRows, tableExportLimits, tableWorkbook, tablePrintHtml } from '@/utils/table-export.mjs';
import type { TableReport } from '@/types/table-export';
import { operationalPage, operationalReport, operationalFilterText, movementIdentity, type OperationalDataset } from '@/services/table-export-operational';
import {historyFetch} from '@/utils/production-history.mjs';
import {warehouseRequestExportRows} from '@/services/table-export-warehouse';

export const runtime = 'nodejs';
export async function POST(request: NextRequest) {
  try {
    verifyOrigin(request);
    const context = await authenticatedClient(historyFetch());
    const input = exportRequest(await request.json());
    const { factory, config, filters, language, dataset, format, sort, direction } = input;
    await authorize(factory, config.permission, 'view', context);
    const meta = await context.db.from('factories').select('id,name,timezone').eq('id', factory).single();
    if (meta.error || meta.data?.id !== factory) throw { code: '42501' };
    const signal = AbortSignal.any([request.signal, AbortSignal.timeout(90000)]);
    const operational = !('mode' in config);
    const identity = dataset === 'warehouse-movements' ? await movementIdentity(context.db, factory, filters, signal) : undefined;
    let requestRows:ReturnType<typeof warehouseRequestExportRows>|undefined;
    const rows = await collectTableRows(async (page: number) => {
      if(dataset==='warehouse-requests'){if(page===1)requestRows=warehouseRequestExportRows(context.db,factory,filters,language);const rows=await requestRows!;return{rows:rows.slice((page-1)*50,page*50),total:rows.length};}
      if (operational) return operationalPage(context.db, factory, dataset as OperationalDataset, filters, sort, direction, page);
      if (!('mode' in config)) throw { code: '22023' };
      const result = await context.db.rpc('quality_read', { factory, query: { mode: config.mode, ...filters, page } });
      if (result.error) throw result.error;
      return result.data;
    }, tableExportLimits[format], signal, 'pageSize' in config ? config.pageSize : 50, 'identity' in config ? config.identity : 'id');
    const mapped = operational ? operationalReport(dataset as OperationalDataset, language, rows, identity) : qualityReport(dataset, language, rows);
    let filterText = mapped.t('all');
    if (operational) filterText = operationalFilterText(dataset as OperationalDataset, filters, sort, direction, mapped.t, identity, language);
    else if (dataset === 'quality-production') {
      const options = await context.db.rpc('quality_read', { factory, query: { mode: 'filters' } });
      if (options.error) throw options.error;
      const labels: Record<string, string> = { date: 'qualityShiftDate', shift: 'productionShift', line: 'line', product: 'product', order: 'productionOrder' };
      const lists: Record<string, string> = { shift: 'shifts', line: 'lines', product: 'products' };
      filterText = Object.entries(filters).map(([key, value]) => {
        const row = options.data?.[lists[key]]?.find((r: Record<string, unknown>) => r.id === value);
        return `${mapped.t(labels[key])}: ${row ? language === 'ar' ? row.name_ar || row.name : row.name : value}`;
      }).join(' · ') || filterText;
    } else filterText = `${mapped.t('productionOrder')}: ${String(rows[0]?.request_code || '—')} · ${mapped.t('tableExportItem')}: ${String(rows[0]?.item_code || '—')}`;
    const report: TableReport = { ...mapped, factory: meta.data.name, timezone: meta.data.timezone || 'UTC', language,
      filters: filterText, timestamp: new Date().toISOString() };
    const result = format === 'excel' ? new Uint8Array(await tableWorkbook(report)) : tablePrintHtml(report);
    // Delivery must still be authorized after all pages and file preparation.
    await authorize(factory, config.permission, 'view', context);
    return new NextResponse(result, { headers: {
      'Content-Type': format === 'excel' ? 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' : 'text/html; charset=utf-8',
      'Content-Disposition': `attachment; filename="${dataset}-${report.timestamp.slice(0, 10)}.${format === 'excel' ? 'xlsx' : 'html'}"`,
      'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff', 'X-Export-Row-Count': String(rows.length),
      'Content-Security-Policy': "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'",
    } });
  } catch (error) {
    if (error instanceof Error && error.message === 'invalid_origin') return historyError({ code: '42501' });
    if (error instanceof Error && /^tableExport(PrintLimit|ExcelLimit|Changed|Precision|Cancelled)$/.test(error.message))
      return NextResponse.json({ error: error.message }, { status: 409, headers: { 'Cache-Control': 'private, no-store' } });
    if (error instanceof SyntaxError) return historyError({ code: '22023' });
    return historyError(error);
  }
}
