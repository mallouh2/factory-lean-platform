import { useEffect, useRef, useState } from "react";
import { Dialog, Field, formatTime, localName } from "@/components/ui";
import { formatLocalInput } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { executionTiming } from "@/utils/execution-queue.mjs";
import {
  nextScheduledOrder, orderAttention, requestAttention,
  requestStatus, sortRequestsForScan,
} from "@/utils/order-overview.mjs";
import { productionProgress, entryQuantities } from "@/utils/production-recording.mjs";
import { requestCreators, requestPresentation, requestQueueMatches, requestStatusMatches } from '@/utils/request-queue.mjs';
import ProductIdentity from '@/components/ProductIdentity';
import HistoryLimitWarning from '@/components/HistoryLimitWarning';
import Configuration from "./Configuration";
import CreateProductionOrder from "./CreateProductionOrder";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
import { requestOriginLabel } from '@/utils/request-origin.mjs';

type Screen = "list" | "details" | "create" | "edit";
type Filter = "all" | "active" | "planned" | "delayed" | "completed" | "cancelled";
const filters: Filter[] = ["all", "active", "planned", "delayed", "completed", "cancelled"];

export default function ProductionOrdersV2(props: FeatureProps & { onPlanItem?: (itemId: string) => void }) {
  const { snapshot: s, t, lang, can, command } = props;
  const [screen, setScreen] = useState<Screen>("list");
  const [filter, setFilter] = useState<Filter[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
  const [createdId, setCreatedId] = useState<string | null>(null);
  const [createDirty, setCreateDirty] = useState(false);
  const [dailyTargetOpen, setDailyTargetOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [search, setSearch] = useState('');
  const [productFilter, setProductFilter] = useState('');
  const [lineFilter, setLineFilter] = useState('');
  const [creatorFilter, setCreatorFilter] = useState('');
  const headingRef = useRef<HTMLHeadingElement>(null);
  const openerRef = useRef<HTMLButtonElement>(null);
  const now = Date.now();
  const zone = String(s.factory?.timezone || "UTC");
  const requests = s.tables.production_requests || [];
  const items = s.tables.production_orders || [];
  const itemsByRequest = new Map<string, Row[]>();
  for (const item of items) {
    const key = String(item.request_id);
    if (!itemsByRequest.has(key)) itemsByRequest.set(key, []);
    itemsByRequest.get(key)?.push(item);
  }
  const products = s.tables.products || [];
  const lines = s.tables.production_lines || [];
  const selected = requests.find((request) => String(request.id) === selectedId);
  const selectedItems = itemsByRequest.get(String(selectedId)) || [];
  const selectedItem = selectedItems.find((item) => String(item.id) === selectedItemId);
  const matchingRequests = requests.filter(request => requestQueueMatches(request,
    itemsByRequest.get(String(request.id)) || [], products,
    { search, product: productFilter, line: lineFilter, creator: creatorFilter }));
  const visible = sortRequestsForScan(
    matchingRequests.filter((request) => requestStatusMatches(request, itemsByRequest.get(String(request.id)) || [], filter, now)),
    items, now,
  );
  const filterCounts = new Map(filters.map((key) => [key,
    matchingRequests.filter((request) => requestStatusMatches(request, itemsByRequest.get(String(request.id)) || [], [key], now)).length]));
  if (filter.includes("planned") && createdId)
    visible.sort((a, b) => Number(String(b.id) === createdId) - Number(String(a.id) === createdId));
  const created = requests.find((request) => String(request.id) === createdId);
  const next = s.truncatedTables?.includes("production_orders") ? undefined : nextScheduledOrder(items, now);
  const nextRequest = next && requests.find((request) => request.id === next.request_id);

  useEffect(() => {
    if (screen !== "list") headingRef.current?.focus();
  }, [screen, selectedId, selectedItemId]);

  const productOf = (item: Row) => products.find((product) => String(product.id) === String(item.product_id));
  const lineOf = (item: Row) => lines.find((line) => String(line.id) === String(item.line_id));
  const itemsOf = (request: Row) => itemsByRequest.get(String(request.id)) || [];
  const unitOf = (item: Row) => t(item.unit === "meter" ? "meterShort" : item.unit === "piece" ? "pieceShort" : "legacyUnit");
  const quantity = (value: unknown) => Number(value).toLocaleString(lang);
  const creators: { id: string; name: string }[] = requestCreators(requests);
  const activeFilterCount = filter.length + Number(Boolean(search)) + Number(Boolean(productFilter)) +
    Number(Boolean(lineFilter)) + Number(Boolean(creatorFilter));
  function statusFilters() {
    return <div className="orders-v2-filters" role="group" aria-label={t('orderStatusFilters')}>
      {filters.map(key => <button type="button" key={key}
        aria-pressed={key === 'all' ? !filter.length : filter.includes(key)}
        onClick={() => setFilter(current => key === 'all' ? [] : current.includes(key)
          ? current.filter(value => value !== key) : [...current, key])}>
        {t(key === 'planned' ? 'plannedWaiting' : key)} ({quantity(filterCounts.get(key) || 0)})
      </button>)}
    </div>;
  }
  function fieldFilters() {
    return <div className="requests-filter-bar">
      <label><span>{t('requestQueueSearch')}</span><input type="search" value={search}
        placeholder={t('requestQueueSearch')} onChange={event => setSearch(event.target.value)} /></label>
      <label><span>{t('requestedBy')}</span><select value={creatorFilter} onChange={event => setCreatorFilter(event.target.value)}>
        <option value="">{t('all')}</option>{creators.map(person => <option key={person.id} value={person.id}>{person.name || t('requestCreatorNotRecorded')}</option>)}
      </select></label>
      <label><span>{t('product')}</span><select value={productFilter} onChange={event => setProductFilter(event.target.value)}>
        <option value="">{t('all')}</option>{products.map(product => <option key={String(product.id)} value={String(product.id)}>{localName(product, lang)}</option>)}
      </select></label>
      <label><span>{t('line')}</span><select value={lineFilter} onChange={event => setLineFilter(event.target.value)}>
        <option value="">{t('all')}</option>{lines.map(line => <option key={String(line.id)} value={String(line.id)}>{localName(line, lang)}</option>)}
      </select></label>
      {activeFilterCount > 0 && <button type="button" onClick={() => {
        setSearch(''); setProductFilter(''); setLineFilter(''); setCreatorFilter(''); setFilter([]);
      }}>{t('historyClear')}</button>}
    </div>;
  }
  function backToList() {
    setScreen("list");
    setDailyTargetOpen(false);
    requestAnimationFrame(() => { if (openerRef.current?.isConnected) openerRef.current.focus(); });
  }
  function statusChip(status: string, attention: string | null, label = status, state = status) {
    return <span className="orders-v2-chips">
      <span className={`orders-v2-chip orders-v2-chip-${status}`} data-state={state}><span aria-hidden="true">●</span> {t(label)}</span>
      {attention && <span className="orders-v2-chip orders-v2-chip-delay"><span aria-hidden="true">!</span> {t("delayed")}</span>}
    </span>;
  }
  function itemProgress(item: Row) {
    const target = Number(item.target_quantity);
    const produced = productionProgress(item).good;
    if (!Number.isFinite(target) || target <= 0 || !Number.isFinite(produced)) return null;
    return <div className="orders-v2-progress">
      <progress value={Math.min(Math.max(produced, 0), target)} max={target}
        aria-label={`${t("orderProgressNow")}: ${quantity(produced)} / ${quantity(target)} ${unitOf(item)}`} />
      <span><bdi dir="ltr">{quantity(produced)} / {quantity(target)}</bdi> {unitOf(item)}</span>
    </div>;
  }

  if (screen === "create" || screen === "edit") {
    const leaveCreate = () => {
      if (screen === "create" && createDirty && !confirm(t("discardRequestDraft"))) return false;
      setCreateDirty(false);
      return true;
    };
    return <section className="orders-v2 orders-v2-subscreen ops-workbench" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <button className="orders-v2-back" onClick={() => {
        if (screen === "edit") { setScreen("details"); return; }
        if (leaveCreate()) backToList();
      }}>
        <span aria-hidden="true" className="orders-v2-back-arrow">←</span> {t("backToOrders")}
      </button>
      <header className="orders-v2-page-head"><div>
        <p>{t("orders")}</p>
        <h2 ref={headingRef} tabIndex={-1}>{t(screen === "create" ? "createProductionRequest" : "planProductItem")}</h2>
        {screen === "create" ? <p className="orders-v2-help">{t("orderCreationSteps")}</p> :
          selectedItem && <p className="orders-v2-help" dir="auto">{localName(productOf(selectedItem), lang)}</p>}
      </div></header>
      {screen === "create" ? <CreateProductionOrder {...props} onCancel={() => { if (leaveCreate()) backToList(); }}
        onDirtyChange={setCreateDirty}
        onCreated={(id) => { setCreatedId(id); setFilter(["planned"]); backToList(); }} /> :
        selectedItem && <Configuration key={String(selectedItem.id)} {...props} view="orders"
          standalone={{ record: selectedItem, onSaved: () => setScreen("details"), onCancel: () => setScreen("details") }} />}
    </section>;
  }

  if (screen === "details" && selected) {
    const attention = requestAttention(selectedItems, now);
    const completed = selectedItems.filter((item) => item.status === "completed").length;
    return <section className="orders-v2 orders-v2-subscreen ops-workbench" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <button className="orders-v2-back" onClick={backToList}>
        <span aria-hidden="true" className="orders-v2-back-arrow">←</span> {t("backToOrders")}
      </button>
      <header className="orders-v2-detail-head">
        <div><p><bdi dir="ltr">{String(selected.code)}</bdi></p>
          <h2 ref={headingRef} tabIndex={-1} dir="auto">{String(selected.name)}</h2>
          <strong>{t("itemsCompleted").replace("{completed}", String(completed)).replace("{total}", String(selectedItems.length))}</strong>
        </div>
        {statusChip(requestStatus(selectedItems), attention)}
      </header>
      {attention && <p className="orders-v2-attention" role="status">{t(attention)}</p>}
      <section className="orders-v2-surface orders-v2-request-facts" aria-label={t("requestDetails")}>
        <dl className="orders-v2-facts">
          <div><dt>{t('requestOrigin')}</dt><dd>{t(requestOriginLabel(selected.request_type))}</dd></div>
          <div><dt>{t(selected.request_type === 'INTERNAL_PRODUCTION' ? 'internalCreatedBy' : 'requestedBy')}</dt><dd dir="auto">{String(selected.requested_by_name || t("requestCreatorNotRecorded"))}</dd></div>
          <div><dt>{t('internalCreatedAt')}</dt><dd>{formatTime(selected.created_at,lang,String(s.factory?.timezone || 'UTC'))}</dd></div>
          <div><dt>{t("priority")}</dt>
            <dd className={["high", "urgent"].includes(String(selected.priority)) ? "orders-v2-priority" : undefined}>
              {t(`priority_${selected.priority || "normal"}`)}</dd></div>
          {selected.required_by && <div><dt>{t("requiredBy")}</dt><dd>{formatTime(selected.required_by, lang, zone)}</dd></div>}
          {selected.notes && <div><dt>{t(selected.request_type === 'INTERNAL_PRODUCTION' ? 'internalProductionReason' : 'notes')}</dt><dd dir="auto">{String(selected.notes)}</dd></div>}
        </dl>
      </section>
      <section className="orders-v2-items" aria-label={t("requestProducts")}>
        <h3>{t("requestProducts")}</h3>
        {selectedItems.map((item) => {
          const product = productOf(item);
          const line = lineOf(item);
          const timing = executionTiming(item, now);
          const itemEntries = (s.tables.production_entries || [])
            .filter((entry) => String(entry.order_id) === String(item.id))
            .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
          return <article className="orders-v2-surface orders-v2-item" key={String(item.id)}>
            <div className="orders-v2-item-head">
              <div><h4 dir="auto"><ProductIdentity productId={item.product_id} productItemId={item.id}>{product ? localName(product, lang) : t("notAvailable")}</ProductIdentity></h4>
                <span>{quantity(item.target_quantity)} {unitOf(item)}</span></div>
              {statusChip(String(item.status || "planned"), orderAttention(item, now))}
            </div>
            {itemProgress(item)}
            <dl className="recording-figures">{(["required", "good", "remaining", "scrap", "overproduction"] as const).map(key => <div key={key}><dt>{t({required:"recordingRequired",good:"recordingGoodSoFar",remaining:"recordingRemaining",scrap:"recordingScrap",overproduction:"recordingOverproduction"}[key])}</dt><dd>{quantity(productionProgress(item)[key])} {unitOf(item)}</dd></div>)}<div><dt>{t("orderProgressNow")}</dt><dd>{quantity(productionProgress(item).percent)}%</dd></div></dl>
            <dl className="orders-v2-facts">
              <div><dt>{t("line")}</dt><dd dir="auto">{line ? localName(line, lang) : t("unassigned")}</dd></div>
              {item.start_time && <div><dt>{t("executionPlannedStart")}</dt><dd>{formatTime(item.start_time, lang, zone)}</dd></div>}
              {item.actual_start && <div><dt>{t("executionActualStart")}</dt><dd>{formatTime(item.actual_start, lang, zone)}</dd></div>}
              {item.expected_finish && <div><dt>{t("executionPlannedFinish")}</dt><dd>{formatTime(item.expected_finish, lang, zone)}</dd></div>}
              {item.actual_finish && <div><dt>{t("executionActualFinish")}</dt><dd>{formatTime(item.actual_finish, lang, zone)}</dd></div>}
              {timing.startVarianceMinutes !== null && <div><dt>{t("executionStartVariance")}</dt><dd><bdi dir="ltr">{formatDuration(timing.startVarianceMinutes, lang, true)}</bdi></dd></div>}
              {timing.finishVarianceMinutes !== null && <div><dt>{t("executionFinishVariance")}</dt><dd><bdi dir="ltr">{formatDuration(timing.finishVarianceMinutes, lang, true)}</bdi></dd></div>}
            </dl>
            {can("orders", "edit") && <div className="orders-v2-detail-actions">
              {item.status === "planned" &&
              <button className="primary" onClick={() => props.onPlanItem
                ? props.onPlanItem(String(item.id))
                : (setSelectedItemId(String(item.id)), setScreen("edit"))}>{t("planScheduleOrder")}</button>}
              {["planned", "active"].includes(String(item.status)) &&
                <button onClick={() => { setSelectedItemId(String(item.id)); setDailyTargetOpen(true); }}>{t("dailyTarget")}</button>}
            </div>}
            {itemEntries.length > 0 && <details className="orders-v2-item-entries">
              <summary>{t("recentProductionEntries")}</summary>
              <ol>{itemEntries.map((entry) => <li key={String(entry.id)}>
                {formatTime(entry.created_at, lang, zone)} · +{quantity(entryQuantities(entry).good)} {unitOf(item)}
              </li>)}</ol>
            </details>}
          </article>;
        })}
      </section>
      {dailyTargetOpen && selectedItem && <Dialog title={t("dailyTarget")} t={t} onClose={() => setDailyTargetOpen(false)}>
        <form onSubmit={async (event) => {
          event.preventDefault();
          const form = new FormData(event.currentTarget);
          setBusy(true);
          try {
            await command("set_daily_target", { factory: s.factory?.id, production_order: selectedItem.id,
              day: form.get("day"), target: Number(form.get("target")) });
            setDailyTargetOpen(false);
          } catch { /* Shared command handler reports the error. */ }
          finally { setBusy(false); }
        }}>
          <Field label={t("day")}><input name="day" type="date" required
            defaultValue={formatLocalInput(new Date().toISOString(), zone).slice(0, 10)} /></Field>
          <Field label={t("productionTarget")}><input name="target" type="number" min="1" required /></Field>
          <button className="primary" disabled={busy}>{t("save")}</button>
        </form>
      </Dialog>}
    </section>;
  }

  return <section className="orders-v2 ops-workbench" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <header className="orders-v2-page-head">
      <p className="ops-page-subtitle">{t('requestsOperationalSubtitle')}</p>
      {can("orders", "create") && <button className="primary" onClick={(event) => {
        openerRef.current = event.currentTarget; setCreatedId(null); setScreen("create");
      }}>+ {t("createProductionRequest")}</button>}
    </header>
    <HistoryLimitWarning snapshot={s} tables={['production_requests', 'production_orders']} t={t} />
    {created && <p className="orders-v2-created" role="status">
      {t("requestReadyForPlanning")} · <bdi dir="ltr">{String(created.code)}</bdi>
    </p>}
    {next && <div className="orders-v2-next">
      <span>{t("nextScheduledStart")}</span>
      <strong><bdi dir="ltr">{String(nextRequest?.code || next.code)}</bdi> · {localName(productOf(next), lang)}</strong>
      <time>{formatTime(next.start_time, lang, zone)}</time>
    </div>}
    <div className="requests-desktop-filters">{statusFilters()}{fieldFilters()}</div>
    <button type="button" className="requests-mobile-filter" popoverTarget="requests-filter-sheet"
      aria-haspopup="dialog">{t('historyFilters')}{activeFilterCount > 0 && ` (${quantity(activeFilterCount)})`}</button>
    <div id="requests-filter-sheet" popover="auto" role="dialog" aria-label={t('historyFilters')}
      className="requests-filter-sheet" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
      <header><strong>{t('historyFilters')}</strong><button type="button" popoverTarget="requests-filter-sheet"
        popoverTargetAction="hide" aria-label={t('close')}>×</button></header>
      {statusFilters()}{fieldFilters()}
    </div>
    {visible.length ? <div className="orders-v2-list">
      <div className="requests-list-head" aria-hidden="true"><span>{t('orders')}</span><span>{t('requestProducts')}</span>
        <span>{t('planningLineSchedule')}</span><span>{t('requiredBy')}</span><span>{t('status')}</span></div>
      {visible.map((request) => {
        const requestItems = itemsOf(request);
        const attention = requestAttention(requestItems, now);
        const display = requestPresentation(request, requestItems, now);
        const completed = requestItems.filter((item) => item.status === "completed").length;
        return <button key={String(request.id)} data-state={display.tone} className={`orders-v2-row${attention ? " orders-v2-row-attention" : ""}`}
          onClick={(event) => { openerRef.current = event.currentTarget; setCreatedId(null); setSelectedId(String(request.id)); setScreen("details"); }}>
          <span className="orders-v2-identity">
            <strong dir="auto">{String(request.name)}</strong>
            <small><bdi dir="ltr">{String(request.code)}</bdi></small>
            <small>{t(requestOriginLabel(request.request_type))}</small>
            <small className="requests-requester">{t(request.request_type === 'INTERNAL_PRODUCTION' ? 'internalCreatedBy' : 'requestedBy')}: {String(request.requested_by_name || t('requestCreatorNotRecorded'))}</small>
            <span className="orders-v2-row-progress">{t('itemsCompleted').replace('{completed}', String(completed)).replace('{total}', String(requestItems.length))}</span>
          </span>
          <span className="orders-v2-line"><small>{t("requestProducts")}</small>
            {t(requestItems.length === 1 ? "productCountOne" : "productCount").replace("{count}", String(requestItems.length))}
            <span className="orders-v2-quantities">{requestItems.slice(0, 2).map((item) =>
              <span key={String(item.id)} dir="auto"><ProductIdentity productId={item.product_id} productItemId={item.id}>{localName(productOf(item), lang)}: {quantity(item.target_quantity)} {unitOf(item)}</ProductIdentity></span>)}
              {requestItems.length > 2 &&
                <span dir="auto">{t("moreProducts").replace("{count}", String(requestItems.length - 2))}</span>}
            </span>
          </span>
          <span className="requests-schedule">{requestItems.slice(0, 2).map(item => <span key={String(item.id)}>
            <strong dir="auto">{item.line_id ? localName(lineOf(item), lang) :
              t(item.status === 'planned' ? 'requestAwaitingPlanning' : 'requestScheduleNotRecorded')}</strong>
            {Boolean(item.line_id && item.start_time) && <span><small>{t('executionPlannedStart')}: {formatTime(item.start_time, lang, zone)}</small>
              <small>{t('executionPlannedFinish')}: {formatTime(item.expected_finish, lang, zone)}</small></span>}
            {item.planning_locked_at && <small>🔒 {t('planningLocked')}</small>}
          </span>)}</span>
          <span className={'orders-v2-timing' + (display.overdue ? ' requests-due-passed' : '')}>
            <small className="requests-mobile-label">{t('requiredBy')}</small>
            <time dateTime={request.required_by ? String(request.required_by) : undefined}>{request.required_by ? formatTime(request.required_by, lang, zone) : t('notSpecified')}</time>
            {display.overdue && <small>! {t('requestsDeadlinePassed')}</small>}
          </span>
          <span className="orders-v2-row-status">
            {statusChip(display.status, attention, display.label, display.state)}
            {["high", "urgent"].includes(String(request.priority)) &&
              <small className="orders-v2-priority">! {t(`priority_${request.priority}`)}</small>}
            {attention && <small>{t(attention)}</small>}
          </span>
        </button>;
      })}
    </div> : <p className="orders-v2-empty">{requests.length ? t("noResults") : t("noRequestsYet")}</p>}
  </section>;
}
