import {warehouseColumnTitle} from '@/utils/warehouse-view.mjs';
import en from '@/locales/en.json';
import ar from '@/locales/ar.json';
import { historyUuid } from './history-response';
import { parseHistoryQuery } from '@/utils/production-history.mjs';
import { inventoryColumns, warehouseVisibleColumns, inventoryChoices, validInventoryFilters } from '@/utils/warehouse-inventory.mjs';
import { readProductionHistory } from './production-history';
import type { authenticatedClient } from './authorization';
import type { ExportColumn } from '@/types/table-export';
import {warehouseSupplementReport} from './table-export-warehouse';
import {warehouseRequestLabels} from '@/utils/warehouse-request-rows.mjs';

export const operationalDatasets = {
  'production-history': { permission: 'orders', title: 'productionHistory', pageSize: 50, identity: 'id' },
  'warehouse-stock': { permission: 'warehouse', title: 'inventoryCatalogue', pageSize: 50, identity: 'row_key' },
  'warehouse-movements': { permission: 'warehouse', title: 'stockMovements', pageSize: 25, identity: 'id' },
  'warehouse-stored-wip': {permission:'warehouse',title:'warehouseStoredWip',pageSize:50,identity:'row_key'},
  'warehouse-requests': {permission:'warehouse',title:'navWarehouseRequests',pageSize:50,identity:'row_key'},
} as const;
export type OperationalDataset = keyof typeof operationalDatasets;
type Client = Awaited<ReturnType<typeof authenticatedClient>>['db'];
type Row = Record<string, unknown>;
const invalid = (): never => { throw { code: '22023' }; };
const historyKeys = ['request', 'product', 'unit', 'technician', 'shift', 'from', 'to', 'scrap', 'minimum_scrap', 'corrected', 'measurement_unit', 'scrap_metric', 'scrap_scope',
  ...['good', 'scrap', 'unfinished'].flatMap(k => [`${k}_op`, `${k}_min`, `${k}_max`])];
const validDate = (value: string) => /^\d{4}-\d{2}-\d{2}$/.test(value) && !value.startsWith('0000') && Number.isFinite(Date.parse(value)) && new Date(value).toISOString().slice(0, 10) === value;

export function operationalRequest(dataset: OperationalDataset, filters: Row, sort: unknown, direction: unknown) {
  if ((sort !== undefined && typeof sort !== 'string') || (direction !== undefined && typeof direction !== 'string')) invalid();
  if(dataset==='warehouse-stored-wip'){if(sort!==undefined||direction!==undefined||Object.keys(filters).length)invalid();return{filters,sort:undefined,direction:undefined};}
  if(dataset==='warehouse-requests'){
    if(filters.status!==undefined&&(typeof filters.status!=='string'||!['active','completed','all'].includes(filters.status)))invalid();
    if(sort!==undefined||direction!==undefined||Object.keys(filters).some(k=>!['department_page','kind','search','status'].includes(k))||!Number.isSafeInteger(filters.department_page)||Number(filters.department_page)<1||Number(filters.department_page)>1000000||typeof filters.search!=='string'||filters.search.length>200||typeof filters.kind!=='string'||!['','issue','unfinished','receipt','acknowledge','dispatch','raw-return','production-stock'].includes(filters.kind))invalid();
    return{filters,sort:undefined,direction:undefined};
  }
  if (dataset === 'production-history') {
    if (Object.entries(filters).some(([key, v]) => !historyKeys.includes(key) || typeof v !== 'string' || v.length > 3000)) invalid();
    const f = filters as Record<string, string>;
    for (const key of ['from', 'to']) if (f[key] && !validDate(f[key])) invalid();
    for (const key of ['request', 'product', 'technician', 'shift', 'unit']) for (const value of (f[key] || '').split(',').filter(Boolean)) {
      if (value === 'unknown' && ['technician', 'shift'].includes(key)) continue;
      if (key === 'unit') { if (!/^(line|machine):[0-9a-f-]{36}$/i.test(value)) invalid(); historyUuid(value.split(':')[1]); }
      else historyUuid(value);
    }
    if (f.corrected && !f.corrected.split(',').every(v => ['yes', 'no', 'all'].includes(v))) invalid();
    if (f.scrap && !['all', 'has'].includes(f.scrap)) invalid();
    for (const key of ['good', 'scrap', 'unfinished']) {
      if ((f[key + '_min'] || f[key + '_max']) && !f[key + '_op']) invalid();
      if (f[key + '_max'] && f[key + '_op'] !== 'between') invalid();
    }
    try {
      const parsed = parseHistoryQuery(new URLSearchParams({ ...f, sort: String(sort ?? 'date'), direction: String(direction ?? 'desc'), page: '1' }));
      return { filters: parsed.filters as Row, sort: parsed.sort_key as string, direction: parsed.sort_direction as string };
    } catch { return invalid(); }
  }
  if (dataset === 'warehouse-stock') {
    if (!validInventoryFilters(filters)) invalid();
    for (const [key, value] of Object.entries(filters)) {
      const kind = inventoryColumns.find((c: string[]) => c[0] === key)?.[2];
      if (kind === 'number') {
        const v = value as Row, keys = ['op', ...(['eq', 'gt', 'lt', 'range'].includes(String(v.op)) ? ['value'] : []), ...(v.op === 'range' ? ['to'] : [])];
        if (Object.keys(v).some(k => !keys.includes(k))) invalid();
      }
      if (kind === 'set' && key !== 'unit' && (value as string[]).some(v => !(inventoryChoices[key as keyof typeof inventoryChoices] || []).includes(v))) invalid();
    }
    const s = sort ?? 'name', d = direction ?? 'asc';
    if (typeof s !== 'string' || !inventoryColumns.some((c: string[]) => c[0] === s) || !['asc', 'desc'].includes(String(d))) invalid();
    return { filters, sort: s as string, direction: d as string };
  }
  if (sort !== undefined || direction !== undefined || Object.keys(filters).some(k => !['item', 'item_type'].includes(k)) || !['finished', 'material'].includes(String(filters.item_type))) invalid();
  return { filters: { item: historyUuid(typeof filters.item === 'string' ? filters.item : null), item_type: filters.item_type }, sort: undefined, direction: undefined };
}

export async function operationalPage(db: Client, factory: string, dataset: OperationalDataset, filters: Row, sort: string | undefined, direction: string | undefined, page: number) {
  if(dataset==='warehouse-stored-wip'){const r=await db.rpc('warehouse_stored_unfinished',{factory,page});if(r.error)throw r.error;return r.data;}
  if (dataset === 'production-history') {
    const data = await readProductionHistory(db, factory, { filters, sort_key: sort, sort_direction: direction, page });
    if (data?.rows?.length) {
      // Product identity only; no extra employee, Quality or inventory table access.
      const ids = [...new Set(data.rows.map((r: Row) => r.product_id).filter(Boolean))];
      if (ids.length) {
        const products = await db.from('products').select('id,code').eq('factory_id', factory).in('id', ids);
        if (products.error) throw products.error;
        data.rows = data.rows.map((r: Row) => ({ ...r, product_code: products.data?.find(p => p.id === r.product_id)?.code ?? null }));
      }
    }
    return data;
  }
  const result = await db.rpc(dataset === 'warehouse-stock' ? 'warehouse_inventory' : 'warehouse_movements', dataset === 'warehouse-stock'
    ? { factory, filters, sort, direction, page } : { factory, item: filters.item, item_type: filters.item_type, page });
  if (result.error) throw result.error;
  return result.data;
}

// Movement history is selected by item, not a global ledger. Resolve its display identity
// through the existing Warehouse-authorized catalogue, without requiring Products permission.
export async function movementIdentity(db: Client, factory: string, filters: Row, signal: AbortSignal) {
  for (let page = 1; page <= 200; page++) {
    if (signal.aborted) throw Error('tableExportCancelled');
    const result = await db.rpc('warehouse_inventory', { factory, page, filters: {}, sort: 'name', direction: 'asc' });
    if (result.error) throw result.error;
    const data = result.data;
    if (!data || !Array.isArray(data.rows) || !Number.isSafeInteger(data.total)) throw Error('tableExportChanged');
    const row = data.rows.find((r: Row) => r.id === filters.item && r.entity === filters.item_type);
    if (row) return row as Row;
    if (page * 50 >= data.total) throw { code: 'P0002' };
  }
  throw Error('tableExportExcelLimit');
}

export function operationalReport(dataset: OperationalDataset, language: 'en' | 'ar', rows: Row[], identity?: Row) {
  if(dataset==='warehouse-stored-wip'||dataset==='warehouse-requests')return warehouseSupplementReport(dataset,language,rows);
  const dictionary: Record<string, string> = language === 'ar' ? ar : en, t = (key: string) => dictionary[key] || key;
  const name = (r: Row, key: string) => (language === 'ar' ? r[key + '_ar'] || r[key] : r[key]) ?? null;
  const unit = (value: unknown) => value == null ? null : t(String(value));
  const definitions: [string, string, ExportColumn['type']?][] = dataset === 'production-history' ? [
    ['request_code', 'productionOrder'], ['item_code', 'tableExportItem'], ['product_code', 'code'], ['product_name', 'product'],
    ['unit_name', 'recordingUnit'], ['shift_name', 'productionShift'], ['created_at', 'tableExportRecordedAt', 'datetime'],
    ['technician_name', 'recordingTechnician'], ['good_quantity', 'tableExportGross', 'number'], ['effective_good', 'tableExportCorrectedGross', 'number'],
    ['effective_scrap', 'leanDiscardedLegacy', 'number'], ['effective_unfinished', 'unfinishedQuantity', 'number'], ['unit', 'unit'],
    ['effective_scrap_kg', 'leanScrapKg', 'number'], ['corrected', 'historyCorrections'], ['submitter_name', 'recordingSubmittedBy'],
  ] : dataset === 'warehouse-stock' ? (warehouseVisibleColumns as string[][]).map(([key, label, kind]) => [key, warehouseColumnTitle(key), kind === 'number' ? 'number' : undefined]) : [
    ['id', 'tableExportMovement'], ['reference', 'externalReference'], ['created_at', 'tableExportRecordedAt', 'datetime'],
    ['item_name', 'item'], ['item_code', 'code'], ['kind', 'inventoryType'], ['quantity', 'stockMovementDelta', 'number'],
    ['reserved_delta', 'reservedMovementDelta', 'number'], ['unit', 'unit'], ['actor_name', 'receivingActor'], ['note', 'notes'],
  ];
  return { title: t(operationalDatasets[dataset].title), t,
    columns: definitions.map(([key, label, type]) => ({ key, label: t(label), type, width: type === 'number' ? 18 : 24 })),
    rows: rows.map(r => Object.fromEntries(definitions.map(([key]) => {
      let value = r[key] ?? null;
      if (['product_name', 'unit_name', 'shift_name', 'name'].includes(key)) value = name(r, key);
      if (key === 'unit') value = unit(r.unit);
      if (key === 'corrected') value = t(r.corrected ? 'historyCorrected' : 'historyUncorrected');
      if (key === 'item_type') value = t(String(r.item_type));
      if (key === 'replenishment_status') value = t('inventory_' + String(r.replenishment_status));
      if (key === 'kind') value = t('movement_' + String(r.kind));
      if (key === 'item_name') value = identity ? name(identity, 'name') : null;
      if (key === 'item_code') value = dataset === 'warehouse-movements' ? identity?.code ?? null : r.item_code ?? null;
      return [key, value];
    }))) };
}

export function operationalFilterText(dataset: OperationalDataset, filters: Row, sort: string | undefined, direction: string | undefined, t: (key: string) => string, identity?: Row, language: 'en' | 'ar' = 'en') {
  if(dataset==='warehouse-stored-wip')return t('all');
  if(dataset==='warehouse-requests')return `${language==='ar'?'صفحة':'Page'} ${filters.department_page} · ${t(String(filters.status||'active'))} · ${filters.search||t('all')} · ${filters.kind?warehouseRequestLabels(language)[filters.kind as keyof ReturnType<typeof warehouseRequestLabels>]:t('all')}`;
  const labels: Record<string, string> = { from: 'historyFrom', to: 'historyTo', request: 'productionOrder', product: 'product', unit: 'recordingUnit', technician: 'recordingTechnician', shift: 'productionShift', corrected: 'historyCorrections', measurement_unit: 'unit', scrap: 'leanDiscardedLegacy', minimum_scrap: 'historyMinimum', scrap_metric: 'historyMetric', scrap_scope: 'historyScope' };
  const translated = (key: string, value: unknown) => {
    const v = String(value);
    if (key.endsWith('_op')) return t('historyOperator_' + v);
    if (key === 'scrap_scope') return t(v === 'shift' ? 'historyPerShift' : 'historyPerEntry');
    if (key === 'scrap_metric') return t(v === 'percentage' ? 'historyScrapPercentage' : 'historyScrapQuantity');
    if (key === 'replenishment_status') return t('inventory_' + v);
    if (key === 'supply_source') return t('supply_' + v);
    if (key === 'corrected') return v.split(',').map(x => t(x === 'yes' ? 'historyCorrected' : x === 'no' ? 'historyUncorrected' : 'all')).join(', ');
    if (key === 'scrap') return t(v === 'has' ? 'historyHasScrap' : 'all');
    if (key === 'item_type' || key === 'measurement_unit' || (key === 'unit' && dataset === 'warehouse-stock')) return t(v);
    return v;
  };
  const values = dataset === 'warehouse-movements' ? [`${t('item')}: ${identity ? String(language === 'ar' ? identity.name_ar || identity.name : identity.name) : '—'} · ${String(identity?.code || '—')}`]
    : Object.entries(filters).map(([key, value]) => {
      const label = dataset === 'warehouse-stock' ? inventoryColumns.find((c: string[]) => c[0] === key)?.[1] : labels[key] || (key.startsWith('good') ? 'recordingGood' : key.startsWith('unfinished') ? 'unfinishedQuantity' : 'leanDiscardedLegacy');
      const display = Array.isArray(value) ? value.map(v => translated(key, v)).join(', ') : value && typeof value === 'object'
        ? `${t('inventoryOp_' + String((value as Row).op))} ${(value as Row).value ?? ''}${(value as Row).to == null ? '' : ' – ' + (value as Row).to}` : translated(key, value);
      const suffix = key.endsWith('_op') ? 'historyCondition' : key.endsWith('_min') ? 'historyMinimum' : key.endsWith('_max') ? 'historyMaximum' : '';
      return `${t(label || key)}${suffix ? ' · ' + t(suffix) : ''}: ${display}`;
    });
  if (sort) values.push(`${t('historySort')}: ${t(dataset === 'warehouse-stock' ? inventoryColumns.find((c: string[]) => c[0] === sort)![1] : sort === 'date' ? 'date' : labels[sort] || (sort === 'good' ? 'recordingGood' : sort === 'unfinished' ? 'unfinishedQuantity' : 'leanDiscardedLegacy'))} · ${t(direction === 'asc' ? 'historyAscending' : 'historyDescending')}`);
  return values.join(' · ') || t('all');
}
