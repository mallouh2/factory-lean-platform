// Application export allowlist. Never accept a table or column name from the browser.
import ExcelJS from 'exceljs';

const dataset = (sheet, table, fields, order = 'id') => ({ sheet, table,
  fields: fields.split(' '), order: order.split(' ') });
export const exportDatasets = [
  dataset('Factory','factories','id name industry timezone working_days_mask workday_start workday_end delivery_buffer_days created_at'),
  dataset('Members','memberships','id user_id display_name job_title job_title_ar is_owner status created_at'),
  dataset('Permission Packages','permission_packages','id name name_ar description template_key revision created_at updated_at'),
  dataset('Package Contents','permission_package_permissions','id package_id module action'),
  dataset('Package Assignments','member_permission_packages','id user_id package_id created_at created_by'),
  dataset('Direct Permissions','user_permissions','user_id module action created_at created_by','user_id module action'),
  dataset('Areas','areas','id name name_ar archived'),
  dataset('Lines','production_lines','id name name_ar code area_id archived paused_at pause_reason'),
  dataset('Machines','work_centers','id name name_ar code line_id category_id type status dependency_mode buffer_minutes impact_scope position archived'),
  dataset('Machine Categories','work_center_categories','id name name_ar icon_key archived'),
  dataset('Machine Alternatives','work_center_alternatives','work_center_id alternative_id','work_center_id alternative_id'),
  dataset('Shifts','production_shifts','id name name_ar start_time end_time archived'),
  dataset('Products','products','id name name_ar code product_kind stage supply_source stock_unit unit_weight_kg formula_product_id minimum_stock maximum_stock'),
  dataset('Materials','materials','id name name_ar code unit inventory_kind minimum_stock maximum_stock'),
  dataset('Recipes','bom_versions','id product_id version batch_quantity output_unit created_at'),
  dataset('Recipe Ingredients','bom_items','id bom_id material_id quantity unit waste_allowance'),
  dataset('Product Capabilities','work_center_capabilities','work_center_id product_id rate rate_unit setup_minutes','work_center_id product_id'),
  dataset('Sales Orders','sales_orders','id code customer_reference status requested_by requested_delivery promised_delivery safety_buffer_days notes approved_at approved_by created_at'),
  dataset('Sales Items','sales_order_lines','id order_id product_id quantity unit release_when_ready dispatched_quantity'),
  dataset('Reservations','finished_goods_reservations','id line_id quantity'),
  dataset('Material Reservations','inventory_reservations','id material_id order_id quantity released_at'),
  dataset('Incoming Allocations','sales_incoming_allocations','id line_id item_id quantity received_quantity released_quantity created_at'),
  dataset('Production Requests','production_requests','id code name request_type priority required_by requested_by requested_by_name notes created_at'),
  dataset('Planning','production_orders','id code request_id product_id line_id unit target_quantity status start_time expected_finish planning_locked_at planning_locked_by'),
  dataset('Planning History','production_plan_revisions','id item_id revision_no event before_line_id before_start before_finish after_line_id after_start after_finish reason_code reason_note changed_by_name changed_at'),
  dataset('Production Execution','production_orders','id code request_id product_id line_id unit status target_quantity good_quantity remaining_quantity actual_start actual_finish'),
  dataset('Production Recording','production_entries','id order_id line_id work_center_id technician_id unit shift_id created_at created_by effective_good effective_scrap_kg effective_startup_kg effective_unfinished produced_weight_kg weight_kg_per_unit input_lot_id input_quantity effective_scrap effective_remaining_work notes'),
  dataset('Production Corrections','production_entry_corrections','id entry_id previous_good corrected_good previous_scrap_kg corrected_scrap_kg previous_unfinished corrected_unfinished reason created_by created_at'),
  dataset('Scrap','lean_scrap_events','id entry_id line_id product_id downtime_id occurred_at preliminary_cause_id observation response approved_cause_id engineering_note reviewed_by reviewed_at'),
  dataset('WIP','unfinished_lots','id source_entry_id quantity_created quantity_available warehouse_quantity remaining_work created_at created_by'),
  dataset('WIP Processing','unfinished_operations','id lot_id entry_id quantity remaining_work line_id work_center_id created_at created_by'),
  dataset('WIP Movements','unfinished_movements','id lot_id entry_id kind quantity location_delta created_at created_by'),
  dataset('Downtime','downtime_events','id work_center_id line_id order_id started_at ended_at stop_nature planned_activity reason_id initial_note approved_cause_id engineering_note approved_by approved_at notes'),
  dataset('Causes','downtime_reasons','id parent_id name name_ar requires_description'),
  dataset('Production Loss','production_loss_estimates','id event_id model_version calculated_at result'),
  dataset('Actual Production Loss','production_loss_actuals','id event_id actual_loss_minutes actual_lost_output_quantity actual_lost_output_unit scrap_quantity scrap_unit recorded_at recorded_by'),
  dataset('Finished Inventory Movements','finished_goods_movements','id product_id unit kind stock_delta reserved_delta sales_line_id entry_id reason external_reference created_at created_by'),
  dataset('Material Inventory Movements','inventory_transactions','id material_id quantity unit kind reference note created_at created_by'),
  dataset('Good Acknowledgments','production_receipt_acknowledgments','entry_id received_by received_at','entry_id'),
  dataset('Production Material Requests','material_requests','id item_name material_id product_id lot_id production_item_id quantity unit status note requested_by_name created_at issued_by issued_at received_by received_at movement_id reason'),
  dataset('Purchase Requests','purchase_requisitions','id code item_name material_id product_id quantity unit details notes status source_context requested_by_name created_at supplier_id supplier_text purchasing_note received_by received_at receipt_movement_id'),
  dataset('Purchase History','purchase_request_events','id request_id status note supplier_name actor_name created_at'),
  dataset('Suppliers','suppliers','id name primary_contact phone email notes active created_at'),
  dataset('Supplier Categories','supplier_categories','id name'),
  dataset('Supplier Relationships','supplier_category_links','supplier_id category_id relationship','supplier_id category_id'),
  dataset('Maintenance','maintenance_requests','id code title description work_center_id line_id downtime_id priority source status requested_by_name requested_at assigned_to started_at completed_at work_note verified_at verified_by verification_result verification_note cancellation_note'),
  dataset('Lean Standards','lean_standards','id line_id product_id running_percent startup_kg revision created_at'),
  dataset('Lean Initiatives','lean_initiatives','id problem_id product_id title baseline_from baseline_to baseline_hours completed_at verified_at outcome verification_note baseline_evidence verification_evidence created_at'),
  dataset('Lean Actions','lean_actions','id initiative_id title description action_type owner_id due_date status progress_note cancellation_reason created_at updated_at'),
  dataset('Lean Templates','lean_action_templates','id cause_id title name_ar description action_type due_days archived'),
  dataset('Lean Comparisons','lean_saved_comparisons','id problem_id product_id cutoff desired_hours evidence created_at created_by'),
  dataset('Audit Log','audit_logs','id actor_id action entity entity_id created_at'),
];

// Full export requires view access too; never silently produce an incomplete RLS-filtered workbook.
export const exportViewModules = ['factory','employees','roles','lines','centers','orders',
  'sales_orders','warehouse','purchasing','downtime','maintenance','lean','audit'];
export const EXPORT_PAGE_SIZE = 500;
export const EXPORT_MAX_ROWS = 100000;
export const EXPORT_MAX_CELLS = 1000000;
const protectedTables = new Set(['bom_versions','bom_items','sales_orders','sales_order_lines',
  'finished_goods_reservations','sales_incoming_allocations','finished_goods_movements',
  'production_receipt_acknowledgments','material_requests','purchase_requisitions',
  'purchase_request_events','suppliers','supplier_categories','supplier_category_links']);
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
const failed = key => Object.assign(new Error(key), { code: key === 'permission_denied' ? '42501' : '40001' });

/** Bounded, ordered reads under the authenticated caller's RLS. Counts detect changing history. */
export async function readExportTable(db, factory, definition, maxRows = EXPORT_MAX_ROWS) {
  if (!uuid.test(factory) || !exportDatasets.includes(definition)) throw failed('export_invalid');
  const rows = [], seen = new Set(); let total;
  for (let offset = 0; offset <= maxRows; offset += EXPORT_PAGE_SIZE) {
    let data, error, count;
    if (protectedTables.has(definition.table)) {
      const result = await db.rpc('factory_export_page', { factory, dataset: definition.table,
        page: offset / EXPORT_PAGE_SIZE + 1 });
      data = result.data?.rows; count = result.data?.total; error = result.error;
    } else {
      let query = db.from(definition.table).select(['factory_id', ...definition.fields].filter(x =>
        definition.table !== 'factories' || x !== 'factory_id').join(','), { count: 'exact' })
        .eq(definition.table === 'factories' ? 'id' : 'factory_id', factory);
      for (const field of definition.order) query = query.order(field, { ascending: true });
      ({ data, error, count } = await query.range(offset, offset + EXPORT_PAGE_SIZE - 1));
    }
    if (error?.message === 'export_too_large') throw failed('export_too_large');
    if (error) throw error;
    if (!Array.isArray(data) || !Number.isSafeInteger(count) || count < 0) throw failed('export_changed');
    if (count > maxRows) throw failed('export_too_large');
    if (total !== undefined && total !== count) throw failed('export_changed');
    total = count;
    for (const row of data) {
      if ((definition.table === 'factories' ? row.id : row.factory_id) !== factory) throw failed('permission_denied');
      const key = JSON.stringify(definition.order.map(field => row[field]));
      if (seen.has(key)) throw failed('export_changed');
      seen.add(key); rows.push(row);
    }
    if (rows.length === total) return rows;
    if (!data.length || data.length < EXPORT_PAGE_SIZE || rows.length > total) throw failed('export_changed');
  }
  throw failed('export_too_large');
}

export async function readExportPages(read, { maxRows = EXPORT_MAX_ROWS, pageSize } = {}) {
  const rows = []; let total, revision;
  for (let page = 1; page <= Math.ceil(maxRows / (pageSize || 50)) + 1; page++) {
    const data = await read(page);
    if (!Array.isArray(data?.rows) || !Number.isSafeInteger(data.total) || data.total < 0) throw failed('export_changed');
    if (data.total > maxRows) throw failed('export_too_large');
    if (total !== undefined && (total !== data.total || revision !== data.source_revision)) throw failed('export_changed');
    total = data.total; revision = data.source_revision; rows.push(...data.rows);
    if (rows.length === total) return rows;
    if (!data.rows.length || rows.length > total) throw failed('export_changed');
  }
  throw failed('export_too_large');
}

export async function collectFactoryExport(db, factory, startedAt) {
  const sheets = [];
  for (const definition of exportDatasets) sheets.push({ ...definition,
    rows: await readExportTable(db, factory, definition) });
  const readRpc = async (rpc, args) => {
    const { data, error } = await db.rpc(rpc, args);
    if (error) throw error;
    return data;
  };
  const inventory = await readExportPages(page => readRpc('warehouse_inventory',
    { factory, page, filters: {}, sort: 'name', direction: 'asc' }), { pageSize: 50 });
  const from = new Date(Date.parse(startedAt) - 365 * 86400000).toISOString();
  const problems = await readExportPages(page => readRpc('lean_read',
    { factory, query: { mode: 'problem_aggregates', from, to: startedAt, page } }), { pageSize: 100 });
  sheets.push({ sheet: 'Warehouse Inventory', fields: ['name','code','item_type','unit','on_hand',
    'reserved','available','semi_finished','in_production','incoming','projected','minimum_stock','maximum_stock','minimum_status','unit_breakdown'], rows: inventory });
  sheets.push({ sheet: 'Lean Problems', fields: ['mechanism','cause','cause_ar','machine_id','line_id',
    'product_id','frequency','loss_minutes','missing_loss','scrap_kg','missing_scrap','monitor_only',
    'lost_output_by_unit','wip_by_unit','first_at','last_at'], rows: problems });
  const findSheet = name => sheets.find(sheet => sheet.sheet === name);
  const copy = (name, source, fields, keep = () => true) => sheets.push({ sheet: name,
    fields: fields.split(' '), rows: findSheet(source).rows.filter(keep) });
  copy('Production Rates','Product Capabilities','work_center_id product_id rate rate_unit setup_minutes');
  copy('Production History','Production Execution','id code request_id product_id line_id unit target_quantity good_quantity actual_start actual_finish', row => row.status === 'completed');
  copy('Approved Causes','Downtime','id work_center_id approved_cause_id engineering_note approved_by approved_at', row => Boolean(row.approved_cause_id));
  copy('Lean Verification','Lean Initiatives','id problem_id title product_id verified_at outcome verification_note baseline_evidence verification_evidence', row => Boolean(row.verified_at));
  const products = new Map(findSheet('Products').rows.map(row => [row.id, row]));
  const lines = new Map(findSheet('Lines').rows.map(row => [row.id, row]));
  const machines = new Map(findSheet('Machines').rows.map(row => [row.id, row]));
  const people = new Map(findSheet('Members').rows.map(row => [row.user_id, row]));
  const entries = new Map(findSheet('Production Recording').rows.map(row => [row.id, row]));
  const orders = new Map(findSheet('Production Execution').rows.map(row => [row.id, row]));
  const lookups = { product_id: products, line_id: lines, work_center_id: machines,
    machine_id: machines, created_by: people, actor_id: people, received_by: people, verified_by: people, owner_id: people };
  for (const sheet of sheets) {
    sheet.fields = [...sheet.fields];
    for (const [field, lookup] of Object.entries(lookups)) {
      if (!sheet.fields.includes(field)) continue;
      const label = field + '_label'; sheet.fields.push(label);
      sheet.rows = sheet.rows.map(row => ({ ...row, [label]: lookup.get(row[field])?.name || lookup.get(row[field])?.display_name || null }));
    }
    if (['WIP','WIP Processing','WIP Movements','Scrap'].includes(sheet.sheet)) {
      sheet.fields.push('production_unit','product_label');
      if (sheet.sheet === 'Scrap') sheet.fields.push('scrap_kg','startup_kg');
      sheet.rows = sheet.rows.map(row => {
        const entry = entries.get(row.source_entry_id || row.entry_id);
        return { ...row, production_unit: entry?.unit,
          product_label: products.get(orders.get(entry?.order_id)?.product_id)?.name,
          scrap_kg: entry?.effective_scrap_kg, startup_kg: entry?.effective_startup_kg };
      });
    }
    if (sheet.sheet === 'Production Loss') {
      sheet.fields = ['id','event_id','model_version','calculated_at','readiness','raw_stop_minutes',
        'effective_loss_minutes','estimated_lost_output_quantity','unit','estimated_total_scrap','scrap_unit'];
      sheet.rows = sheet.rows.map(row => ({ ...row, ...row.result }));
    }
  }
  return sheets;
}

const secretField = /password|secret|token|api.?key|service.?role|anon.?key|publishable.?key|authorization|credential/i;
export function safeExportValue(value) {
  if (value == null) return null;
  if (typeof value === 'object') {
    const clean = Array.isArray(value) ? value.map(safeExportValue) : Object.fromEntries(
      Object.entries(value).filter(([key]) => !secretField.test(key)).map(([key, item]) => [key, safeExportValue(item)]));
    return clean;
  }
  if (typeof value !== 'string') return value;
  return value.replace(/\b(?:sb_secret_|sbp_)[A-Za-z0-9_-]+|\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|Bearer\s+\S+|postgres(?:ql)?:\/\/[^\s]+|(?:password|service_role_key|access_token)\s*[:=]\s*[^\s,;]+/gi, '[redacted]');
}
const header = field => field.replaceAll('_', ' ').replace(/\b\w/g, x => x.toUpperCase());
const atPath = (row, field) => field.split('.').reduce((item, key) => item?.[key], row);

/** Strings are literal XLSX strings, never formulas or hyperlinks supplied by a user. */
export async function factoryWorkbook({ factory, user, startedAt, completedAt, sheets, language = 'en' }) {
  const workbook = new ExcelJS.Workbook();
  workbook.creator = 'Factory Lean'; workbook.created = new Date(startedAt);
  const timezone = factory.timezone || 'UTC';
  const format = new Intl.DateTimeFormat('en-GB', { timeZone: timezone, dateStyle: 'medium', timeStyle: 'medium', hour12: false });
  const metadata = [{ item: 'Factory', value: factory.name }, { item: 'Factory ID', value: factory.id },
    { item: 'Export started', value: startedAt }, { item: 'Export completed', value: completedAt },
    { item: 'Timezone', value: timezone }, { item: 'Exporting user', value: user.email || user.id },
    { item: 'Exporting user ID', value: user.id },
    { item: 'Scope', value: 'All available operational history. Lean Problems: last 365 days. Blank measurements are unknown, not zero. Units remain separate.' },
    { item: 'Consistency', value: 'Live paginated reads, not a transactional database backup. Stop operational edits and retry if history changes during export.' },
    { item: 'Audit', value: 'Event metadata only; raw before/after payloads and authentication tables excluded.' },
    ...sheets.map(sheet => ({ item: sheet.sheet + ' rows', value: sheet.rows.length }))];
  let cells = 0;
  for (const data of [{ sheet: 'Export Metadata', fields: ['item','value'], rows: metadata }, ...sheets]) {
    cells += data.fields.length * data.rows.length;
    if (cells > EXPORT_MAX_CELLS) throw failed('export_too_large');
    const sheet = workbook.addWorksheet(data.sheet, { views: [{ state: 'frozen', ySplit: 1, rightToLeft: language === 'ar' }] });
    sheet.columns = data.fields.map(field => ({ header: header(field), key: field,
      width: /note|description|evidence|result|value/.test(field) ? 48 : /_at$|_time$|_start$|_finish$/.test(field) ? 25 : /id$/.test(field) ? 38 : 22 }));
    for (const row of data.rows) {
      const values = data.fields.map(field => {
        let value = safeExportValue(atPath(row, field));
        if (typeof value === 'string' && /^\d{4}-\d\d-\d\dT\d\d:/.test(value) && Number.isFinite(Date.parse(value))) value = format.format(new Date(value));
        if (value && typeof value === 'object') value = JSON.stringify(value);
        if (typeof value === 'string' && value.length > 32767) throw failed('export_cell_too_long');
        return value;
      });
      sheet.addRow(values);
    }
    sheet.autoFilter = { from: { row: 1, column: 1 }, to: { row: 1, column: data.fields.length } };
    sheet.eachRow((row, index) => {
      row.alignment = { vertical: 'top', wrapText: true };
      row.eachCell(cell => {
        cell.font = { name: 'Calibri', size: 11, bold: index === 1, color: { argb: 'FF243746' } };
        cell.fill = { type: 'pattern', pattern: 'solid', fgColor: { argb: index === 1 ? 'FFE4EBF1' : index % 2 ? 'FFF0F4F8' : 'FFFFFFFF' } };
      });
    });
  }
  return workbook.xlsx.writeBuffer();
}
