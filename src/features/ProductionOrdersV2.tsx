import { useEffect, useRef, useState } from "react";
import { Dialog, Field, formatTime, localName } from "@/components/ui";
import { formatLocalInput } from "@/utils/manufacturing.mjs";
import {
  nextScheduledOrder, orderAttention, requestAttention, requestMatchesFilter,
  requestStatus, sortRequestsForScan,
} from "@/utils/order-overview.mjs";
import Configuration from "./Configuration";
import CreateProductionOrder from "./CreateProductionOrder";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";

type Screen = "list" | "details" | "create" | "edit";
type Filter = "all" | "active" | "planned" | "delayed" | "completed";
const filters: Filter[] = ["all", "active", "planned", "delayed", "completed"];

export default function ProductionOrdersV2(props: FeatureProps & { onPlanItem?: (itemId: string) => void }) {
  const { snapshot: s, t, lang, can, command } = props;
  const [screen, setScreen] = useState<Screen>("list");
  const [filter, setFilter] = useState<Filter>("all");
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
  const [createdId, setCreatedId] = useState<string | null>(null);
  const [createDirty, setCreateDirty] = useState(false);
  const [dailyTargetOpen, setDailyTargetOpen] = useState(false);
  const [busy, setBusy] = useState(false);
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
  const visible = sortRequestsForScan(
    requests.filter((request) => requestMatchesFilter(request, itemsByRequest.get(String(request.id)) || [], filter, now)),
    items, now,
  );
  const filterCounts = new Map(filters.map((key) => [key,
    requests.filter((request) => requestMatchesFilter(request, itemsByRequest.get(String(request.id)) || [], key, now)).length]));
  if (filter === "planned" && createdId)
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
  function backToList() {
    setScreen("list");
    setDailyTargetOpen(false);
    requestAnimationFrame(() => { if (openerRef.current?.isConnected) openerRef.current.focus(); });
  }
  function statusChip(status: string, attention: string | null) {
    return <span className="orders-v2-chips">
      <span className={`orders-v2-chip orders-v2-chip-${status}`}><span aria-hidden="true">●</span> {t(status)}</span>
      {attention && <span className="orders-v2-chip orders-v2-chip-delay"><span aria-hidden="true">!</span> {t("delayed")}</span>}
    </span>;
  }
  function itemProgress(item: Row) {
    const target = Number(item.target_quantity);
    const produced = Number(item.produced_quantity);
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
    return <section className="orders-v2 orders-v2-subscreen">
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
        onCreated={(id) => { setCreatedId(id); setFilter("planned"); backToList(); }} /> :
        selectedItem && <Configuration key={String(selectedItem.id)} {...props} view="orders"
          standalone={{ record: selectedItem, onSaved: () => setScreen("details"), onCancel: () => setScreen("details") }} />}
    </section>;
  }

  if (screen === "details" && selected) {
    const attention = requestAttention(selectedItems, now);
    const completed = selectedItems.filter((item) => item.status === "completed").length;
    return <section className="orders-v2 orders-v2-subscreen">
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
          <div><dt>{t("requestedBy")}</dt><dd dir="auto">{String(selected.requested_by_name || t("notAvailable"))}</dd></div>
          <div><dt>{t("priority")}</dt>
            <dd className={["high", "urgent"].includes(String(selected.priority)) ? "orders-v2-priority" : undefined}>
              {t(`priority_${selected.priority || "normal"}`)}</dd></div>
          {selected.required_by && <div><dt>{t("requiredBy")}</dt><dd>{formatTime(selected.required_by, lang, zone)}</dd></div>}
          {selected.notes && <div><dt>{t("notes")}</dt><dd dir="auto">{String(selected.notes)}</dd></div>}
        </dl>
      </section>
      <section className="orders-v2-items" aria-label={t("requestProducts")}>
        <h3>{t("requestProducts")}</h3>
        {selectedItems.map((item) => {
          const product = productOf(item);
          const line = lineOf(item);
          const itemEntries = (s.tables.production_entries || [])
            .filter((entry) => String(entry.order_id) === String(item.id))
            .sort((a, b) => String(b.created_at).localeCompare(String(a.created_at))).slice(0, 5);
          return <article className="orders-v2-surface orders-v2-item" key={String(item.id)}>
            <div className="orders-v2-item-head">
              <div><h4 dir="auto">{product ? localName(product, lang) : t("notAvailable")}</h4>
                <span>{quantity(item.target_quantity)} {unitOf(item)}</span></div>
              {statusChip(String(item.status || "planned"), orderAttention(item, now))}
            </div>
            {itemProgress(item)}
            <dl className="orders-v2-facts">
              <div><dt>{t("line")}</dt><dd dir="auto">{line ? localName(line, lang) : t("unassigned")}</dd></div>
              {item.start_time && <div><dt>{t("start_time")}</dt><dd>{formatTime(item.start_time, lang, zone)}</dd></div>}
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
                {formatTime(entry.created_at, lang, zone)} · +{quantity(entry.produced)} {unitOf(item)}
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

  return <section className="orders-v2">
    <header className="orders-v2-page-head">
      <div><h2>{t("orders")}</h2><p>{t("ordersOverviewHelp")}</p></div>
      {can("orders", "create") && <button className="primary" onClick={(event) => {
        openerRef.current = event.currentTarget; setCreatedId(null); setScreen("create");
      }}>+ {t("createProductionRequest")}</button>}
    </header>
    {created && <p className="orders-v2-created" role="status">
      {t("requestReadyForPlanning")} · <bdi dir="ltr">{String(created.code)}</bdi>
    </p>}
    {next && <div className="orders-v2-next">
      <span>{t("nextScheduledStart")}</span>
      <strong><bdi dir="ltr">{String(nextRequest?.code || next.code)}</bdi> · {localName(productOf(next), lang)}</strong>
      <time>{formatTime(next.start_time, lang, zone)}</time>
    </div>}
    <nav className="orders-v2-filters" aria-label={t("orderStatusFilters")}>
      {filters.map((key) => <button key={key} aria-pressed={filter === key}
        onClick={() => setFilter(key)}>{t(key === "planned" ? "plannedWaiting" : key)}
        ({quantity(filterCounts.get(key) || 0)})</button>)}
    </nav>
    {visible.length ? <div className="orders-v2-list">
      {visible.map((request) => {
        const requestItems = itemsOf(request);
        const attention = requestAttention(requestItems, now);
        const completed = requestItems.filter((item) => item.status === "completed").length;
        return <button key={String(request.id)} className={`orders-v2-row${attention ? " orders-v2-row-attention" : ""}`}
          onClick={(event) => { openerRef.current = event.currentTarget; setCreatedId(null); setSelectedId(String(request.id)); setScreen("details"); }}>
          <span className="orders-v2-identity">
            <strong dir="auto">{String(request.name)}</strong>
            <small><bdi dir="ltr">{String(request.code)}</bdi></small>
          </span>
          <span className="orders-v2-line"><small>{t("requestProducts")}</small>
            {t(requestItems.length === 1 ? "productCountOne" : "productCount").replace("{count}", String(requestItems.length))}
            <span className="orders-v2-quantities">{requestItems.slice(0, 2).map((item) =>
              <span key={String(item.id)} dir="auto">{localName(productOf(item), lang)}: {quantity(item.target_quantity)} {unitOf(item)}</span>)}
              {requestItems.length > 2 &&
                <span dir="auto">{t("moreProducts").replace("{count}", String(requestItems.length - 2))}</span>}
            </span>
          </span>
          <span className="orders-v2-timing"><small>{t("requestedBy")}</small>
            <span dir="auto">{String(request.requested_by_name || t("notAvailable"))}</span>
            {request.required_by && <small>{t("requiredBy")}: {formatTime(request.required_by, lang, zone)}</small>}
          </span>
          <span className="orders-v2-row-progress">{t("itemsCompleted").replace("{completed}", String(completed)).replace("{total}", String(requestItems.length))}</span>
          <span className="orders-v2-row-status">
            {statusChip(requestStatus(requestItems), attention)}
            {["high", "urgent"].includes(String(request.priority)) &&
              <small className="orders-v2-priority">! {t(`priority_${request.priority}`)}</small>}
            {attention && <small>{t(attention)}</small>}
          </span>
        </button>;
      })}
    </div> : <p className="orders-v2-empty">{requests.length ? t("noResults") : t("noRequestsYet")}</p>}
  </section>;
}
