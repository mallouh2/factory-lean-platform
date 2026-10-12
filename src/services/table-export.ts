import en from '@/locales/en.json';
import ar from '@/locales/ar.json';
import { historyUuid } from './history-response';
import type { ExportColumn, TableDataset } from '@/types/table-export';
import { operationalDatasets, operationalRequest, type OperationalDataset } from './table-export-operational';

const datasets = {
  'quality-production': { mode: 'board', permission: 'quality', title: 'quality', filters: ['date', 'shift', 'line', 'product', 'order'] },
  'quality-history': { mode: 'history', permission: 'quality_history', title: 'qualityHistory', filters: ['entry'] },
  ...operationalDatasets,
} as const;
export function exportRequest(body: unknown) {
  const invalid = () => { throw { code: '22023' }; };
  if (!body || typeof body !== 'object' || Array.isArray(body)) return invalid();
  const b = body as Record<string, unknown>;
  if (Object.keys(b).some(k => !['factory', 'dataset', 'format', 'language', 'filters', 'sort', 'direction'].includes(k))) return invalid();
  if (typeof b.dataset !== 'string' || !Object.hasOwn(datasets, b.dataset) || typeof b.format !== 'string' || !['excel', 'print'].includes(b.format) || typeof b.language !== 'string' || !['en', 'ar'].includes(b.language)) return invalid();
  const dataset = b.dataset as TableDataset, config = datasets[dataset];
  if (!b.filters || typeof b.filters !== 'object' || Array.isArray(b.filters)) return invalid();
  if (Object.hasOwn(operationalDatasets, dataset)) {
    const selection = operationalRequest(dataset as OperationalDataset, b.filters as Record<string, unknown>, b.sort, b.direction);
    return { factory: historyUuid(typeof b.factory === 'string' ? b.factory : null), dataset, config, ...selection,
      format: b.format as 'excel' | 'print', language: b.language as 'en' | 'ar' };
  }
  if (b.sort !== undefined || b.direction !== undefined || !('filters' in config)) return invalid();
  const filters: Record<string, string> = {};
  for (const [key, value] of Object.entries(b.filters)) {
    if (!(config.filters as readonly string[]).includes(key) || typeof value !== 'string') return invalid();
    if (!value) continue;
    if (key === 'date') {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || value.startsWith('0000') || !Number.isFinite(Date.parse(value)) || new Date(value).toISOString().slice(0, 10) !== value) return invalid();
    } else if (key === 'order') { if (value.length > 100) return invalid(); }
    else historyUuid(value);
    filters[key] = value;
  }
  if (dataset === 'quality-history' && !filters.entry) return invalid();
  return { factory: historyUuid(typeof b.factory === 'string' ? b.factory : null), dataset, config, filters, sort: undefined, direction: undefined,
    format: b.format as 'excel' | 'print', language: b.language as 'en' | 'ar' };
}
export function qualityReport(dataset: TableDataset, language: 'en' | 'ar', rows: Record<string, unknown>[]) {
  const dictionary: Record<string, string> = language === 'ar' ? ar : en;
  const t = (key: string) => dictionary[key] || key;
  const named = (r: Record<string, unknown>, key: string) => language === 'ar' ? r[key + '_ar'] || r[key] : r[key];
  const definitions: [string, string, ExportColumn['type']?][] = [
    ['request_code', 'productionOrder'], ['item_code', 'tableExportItem'], ['line_name', 'line'], ['shift_name', 'productionShift'],
    ['shift_date', 'qualityShiftDate'], ['product_code', 'code'], ['product_name', 'product'],
    ...(dataset === 'quality-production' ? [
      ['recorded_good', 'tableExportGross', 'number'], ['current_good', 'qualityCorrected', 'number'],
      ['rejected', 'qualityRejected', 'number'], ['accepted', 'qualityAccepted', 'number'],
    ] as [string, string, ExportColumn['type']?][] : [
      ['quantity', 'qualityRejected', 'number'], ['scrap_kg', 'qualityActualKg', 'number'],
      ['rework_quantity', 'qualityRework', 'number'], ['reason', 'reason'], ['description', 'description'],
      ['disposition', 'tableExportDisposition'], ['status', 'status'], ['actor_name', 'qualityActor'],
    ] as [string, string, ExportColumn['type']?][]),
    ['unit', 'unit'], ['created_at', 'tableExportRecordedAt', 'datetime'],
  ];
  return { title: t(datasets[dataset].title), columns: definitions.map(([key, label, type]) => ({ key, label: t(label), type, width: type === 'number' ? 18 : 24 })),
    rows: rows.map(r => Object.fromEntries(definitions.map(([key]) => {
      let value = r[key] ?? null;
      if (['line_name', 'shift_name', 'product_name', 'reason'].includes(key)) value = named(r, key) ?? null;
      if (key === 'unit') value = r.unit === 'meter' || r.unit === 'piece' ? t(r.unit) : null;
      if (key === 'scrap_kg') value = r.disposition === 'SCRAP' ? r.actual_scrap_kg ?? null : null;
      if (key === 'rework_quantity') value = r.disposition === 'REWORK' ? r.quantity ?? null : null;
      if (key === 'disposition') value = t(r.disposition === 'SCRAP' ? 'qualityScrap' : 'qualityRework');
      if (key === 'status') value = r.reversal ? t('qualityReversed') : t('qualityStatus_' + String((r.notification as Record<string, unknown> | null)?.status || 'OPEN'));
      return [key, value];
    }))), t };
}
