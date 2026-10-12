import ExcelJS from 'exceljs';
import { safeExportValue } from './factory-export.mjs';

export const tableExportLimits = { excel: 10000, print: 500 };
// Existing protected readers own filtering and authorization. Never filter records in the browser.
export async function collectTableRows(read, limit, signal, pageSize = 50, identity = 'id') {
  const collect = async () => {
    const rows = [], ids = new Set(); let total;
    for (let page = 1; ; page++) {
      if (signal?.aborted) throw Error('tableExportCancelled');
      const data = await read(page);
      if (!data || !Array.isArray(data.rows) || !Number.isSafeInteger(data.total) || data.total < 0) throw Error('tableExportChanged');
      if (data.total > limit) throw Error(limit === tableExportLimits.print ? 'tableExportPrintLimit' : 'tableExportExcelLimit');
      if (total !== undefined && total !== data.total) throw Error('tableExportChanged');
      total = data.total;
      if (data.rows.length !== Math.min(pageSize, total - rows.length)) throw Error('tableExportChanged');
      for (const row of data.rows) {
        if (!row[identity] || ids.has(row[identity])) throw Error('tableExportChanged');
        ids.add(row[identity]); rows.push(row);
      }
      if (rows.length === total) return rows;
    }
  };
  const rows = await collect();
  // Readers are paginated, not a transaction snapshot. Refuse detected changes rather than mixed pages.
  if (JSON.stringify(rows) !== JSON.stringify(await collect())) throw Error('tableExportChanged');
  return rows;
}
const escape = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
export function reportValue(value, column, report) {
  if (value === null || value === undefined || value === '') return null;
  if (column.type === 'number') {
    const raw = String(value);
    const coefficient = raw.split(/[eE]/)[0];
    const significant = coefficient.replace(/^[+-]?0*/, '').replace('.', '').replace(/^0+/, '').replace(/0+$/, '');
    if (!/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$/.test(raw) || !Number.isFinite(Number(raw)) || significant.length > 15 || (Number(raw) === 0 && /[1-9]/.test(coefficient))) throw Error('tableExportPrecision');
    return Number(raw);
  }
  if (column.type === 'datetime') {
    const date = new Date(String(value));
    if (!Number.isFinite(date.getTime())) throw Error('tableExportChanged');
    return new Intl.DateTimeFormat(report.language, { timeZone: report.timezone, dateStyle: 'medium', timeStyle: 'short', hourCycle: 'h23' }).format(date);
  }
  const text = String(safeExportValue(String(value)));
  if (text.length > 32767) throw Error('tableExportExcelLimit');
  return text;
}
export function reportMetadata(report) {
  const ar = report.language === 'ar';
  return [[ar ? 'المصنع' : 'Factory', report.factory], [ar ? 'التقرير' : 'Report', report.title],
    [ar ? 'وقت التصدير' : 'Exported at', reportValue(report.timestamp, { type: 'datetime' }, report)],
    [ar ? 'المنطقة الزمنية' : 'Timezone', report.timezone], [ar ? 'الفلاتر' : 'Filters', report.filters],
    [ar ? 'عدد الصفوف' : 'Row count', report.rows.length]];
}
function validateReport(report, format) {
  if (report.rows.length > tableExportLimits[format]) throw Error(format === 'print' ? 'tableExportPrintLimit' : 'tableExportExcelLimit');
  let characters = 0;
  for (const [, value] of reportMetadata(report)) characters += String(reportValue(value, {}, report) ?? '').length;
  for (const row of report.rows) for (const column of report.columns) {
    characters += String(reportValue(row[column.key], column, report) ?? '').length;
    if (characters > (format === 'print' ? 2000000 : 10000000)) throw Error(format === 'print' ? 'tableExportPrintLimit' : 'tableExportExcelLimit');
  }
}
export async function tableWorkbook(report) {
  validateReport(report, 'excel');
  const book = new ExcelJS.Workbook(); book.creator = 'Factory Lean';
  const sheet = book.addWorksheet(report.title.slice(0, 31).replace(/[\\/*?:\[\]]/g, ' '));
  for (const row of reportMetadata(report)) sheet.addRow(row.map(v => typeof v === 'number' ? v : reportValue(v, {}, report)));
  sheet.addRow([]); const header = sheet.addRow(report.columns.map(c => c.label));
  header.font = { bold: true, color: { argb: 'FFFFFFFF' } };
  header.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF112C3C' } };
  sheet.views = [{ state: 'frozen', ySplit: header.number, rightToLeft: report.language === 'ar' }];
  report.columns.forEach((c, i) => { sheet.getColumn(i + 1).width = c.width || 24; if (c.type === 'number') sheet.getColumn(i + 1).numFmt = '0.###############'; });
  for (const row of report.rows) sheet.addRow(report.columns.map(c => reportValue(row[c.key], c, report)));
  sheet.autoFilter = { from: { row: header.number, column: 1 }, to: { row: sheet.rowCount, column: report.columns.length } };
  sheet.eachRow(row => { row.alignment = { vertical: 'top', wrapText: true }; });
  return book.xlsx.writeBuffer();
}
export function tablePrintHtml(report) {
  validateReport(report, 'print');
  const rtl = report.language === 'ar', orientation = report.columns.length > 7 ? 'landscape' : 'portrait';
  return `<!doctype html><html lang="${rtl ? 'ar' : 'en'}" dir="${rtl ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>${escape(report.title)}</title><style>
  @page{size:A4 ${orientation};margin:12mm}*{box-sizing:border-box}body{background:#fff;color:#182939;font:11px Arial,"Noto Sans Arabic",Tahoma,sans-serif;margin:16px}h1{font-size:20px;margin:0 0 12px}dl{display:flex;flex-wrap:wrap;gap:8px 24px;margin:0 0 16px}dl div{max-width:100%;overflow-wrap:anywhere}dt{font-weight:bold}dd{margin:3px 0}table{border-collapse:collapse;width:100%;table-layout:fixed}th,td{padding:6px;border:1px solid #dce4ea;text-align:start;overflow-wrap:anywhere;vertical-align:top}th{background:#f1f4f7}thead{display:table-header-group}tr{break-inside:avoid}button{padding:10px;margin-bottom:16px}@media print{body{margin:0}.print-controls{display:none}}
  </style></head><body><h1>${escape(report.title)}</h1><dl>${reportMetadata(report).map(([k, v]) => `<div><dt>${escape(k)}</dt><dd>${escape(safeExportValue(v))}</dd></div>`).join('')}</dl><table><thead><tr>${report.columns.map(c => `<th scope="col">${escape(c.label)}</th>`).join('')}</tr></thead><tbody>${report.rows.map(row => `<tr>${report.columns.map(c => `<td>${escape(reportValue(row[c.key], c, report) ?? '—')}</td>`).join('')}</tr>`).join('') || `<tr><td colspan="${report.columns.length}">${rtl ? 'لا توجد نتائج' : 'No results'}</td></tr>`}</tbody></table></body></html>`;
}
