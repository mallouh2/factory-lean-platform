export type TableDataset = 'quality-production' | 'quality-history' | 'production-history' | 'warehouse-stock' | 'warehouse-movements' | 'warehouse-stored-wip' | 'warehouse-requests';
export type ExportColumn = { key: string; label: string; type?: 'number' | 'datetime'; width?: number };
export type TableReport = {
  title: string; factory: string; timezone: string; language: 'en' | 'ar'; timestamp: string;
  filters: string; columns: ExportColumn[]; rows: Record<string, unknown>[];
};
