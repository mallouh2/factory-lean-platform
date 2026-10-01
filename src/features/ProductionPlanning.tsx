import { useEffect, useRef, useState } from "react";
import { formatTime, localName } from "@/components/ui";
import { formatLocalInput, localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { lineExecutionQueue } from '@/utils/execution-queue.mjs';
import { productionProgress } from '@/utils/production-recording.mjs';
import { orderAttention } from '@/utils/order-overview.mjs';
import { requestPresentation } from '@/utils/request-queue.mjs';
import ProductIdentity from '@/components/ProductIdentity';
import { productColor } from '@/utils/product-colors.mjs';
import {
  capableLines, deadlineStatus, durationMs, finishAfterWorkingMs, firstAvailable, freeGaps, lineCapacity,
  groupPlanningRequests, isScheduled, panViewStart, workingCalendar, workingSegments, wheelViewStart,
  overlappingItems, planningBoardStatus, planningWarnings, previewPlacement,
  proposeSchedule, sortedLineSchedule, sortPlanningItems, zoomViewStart,
  suggestPlanningSlots,
} from "@/utils/planning.mjs";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";

type Revision = { revision_no: number; event: string; before_line_id: string | null;
  before_start: string | null; before_finish: string | null; after_line_id: string | null;
  after_start: string | null; after_finish: string | null; reason_code: string | null;
  reason_note: string | null; changed_by_name: string | null; changed_at: string };
type PendingReason = { source: "drop" | "save" | "unschedule"; item: string;
  target_line: string | null; planned_start: string | null };
type SlotSuggestion = { lineId: string; start: number; finish: number; setupMs: number;
  productionMs: number; totalMs: number; rate: number; deadline: string;
  load: { percent: number | null; bookedMinutes: number; availableMinutes: number; incomplete: boolean } };
const reasonCodes = ["priority_change", "customer_request", "machine_unavailable", "maintenance",
  "material_delay", "capacity_conflict", "quality_issue", "management_decision", "other"] as const;

export default function ProductionPlanning({ snapshot: s, t, lang, can, command, initialItemId }:
  FeatureProps & { initialItemId?: string | null }) {
  const [editingId, setEditingId] = useState<string | null>(initialItemId || null);
  const [lineId, setLineId] = useState("");
  const [start, setStart] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [zoomIndex, setZoomIndex] = useState(1);
  const [viewStart, setViewStart] = useState(() => Date.parse(localDateTimeToUtc(
    formatLocalInput(new Date().toISOString(), String(s.factory?.timezone || "UTC")).slice(0, 10) + "T00:00",
    String(s.factory?.timezone || "UTC"))));
  const [lineFilter, setLineFilter] = useState("");
  const [priorityFilter, setPriorityFilter] = useState("");
  const [productFilter, setProductFilter] = useState("");
  const [draggingId, setDraggingId] = useState<string | null>(null);
  const [hoverPreview, setHoverPreview] = useState<{
    itemId: string; lineId: string; start: number; finish: number; durationMs?: number;
    productionMs?: number; setupMs?: number; requestedStart?: number;
    rate?: number; error?: string;
  } | null>(null);
  const [optimistic, setOptimistic] = useState<{
    id: string; line_id: string; start_time: string; expected_finish: string;
  } | null>(null);
  const [savingDropId, setSavingDropId] = useState<string | null>(null);
  const [settlingId, setSettlingId] = useState<string | null>(null);
  const [rejectedId, setRejectedId] = useState<string | null>(null);
  const [panning, setPanning] = useState(false);
  const [pendingReason, setPendingReason] = useState<PendingReason | null>(null);
  const [reasonCode, setReasonCode] = useState<string>("");
  const [reasonNote, setReasonNote] = useState("");
  const [history, setHistory] = useState<Revision[] | null>([]);
  const [historyLoading, setHistoryLoading] = useState(false);
  const [slotSearch, setSlotSearch] = useState<{ itemId: string; suggestions: SlotSuggestion[];
    reason: string | null; horizonDays: number } | null>(null);
  const [slotChoice, setSlotChoice] = useState<number | null>(null);
  const headingRef = useRef<HTMLHeadingElement>(null);
  const drawerRef = useRef<HTMLElement>(null);
  const openerRef = useRef<HTMLButtonElement>(null);
  const timelineRef = useRef<HTMLDivElement>(null);
  const slotPanelRef = useRef<HTMLDivElement>(null);
  const reasonSelectRef = useRef<HTMLSelectElement>(null);
  const panStateRef = useRef<{ pointerId: number; x: number; viewStart: number; width: number } | null>(null);
  const draggingRef = useRef<string | null>(null);
  const lastHoverRef = useRef<{ itemId: string; error?: string } | null>(null);
  const zone = String(s.factory?.timezone || "UTC");
  const calendar = workingCalendar(s.factory);
  const orders = (s.tables.production_orders || []).map((order) =>
    optimistic && String(order.id) === optimistic.id ? { ...order, ...optimistic } : order);
  const requests = s.tables.production_requests || [];
  const products = s.tables.products || [];
  const lines = s.tables.production_lines || [];
  const centers = s.tables.work_centers || [];
  const capabilities = s.tables.work_center_capabilities || [];
  const requestById = new Map(requests.map((request) => [String(request.id), request]));
  const active = orders.filter((order) => order.status === "planned");
  const visible = (order: Row) => (!priorityFilter || requestById.get(String(order.request_id))?.priority === priorityFilter) &&
    (!productFilter || String(order.product_id) === productFilter);
  const planningItems = sortPlanningItems(active.filter((order) =>
    !isScheduled(order) && visible(order) &&
    (!lineFilter || capableLines(order, lines, centers, capabilities).some((line: Row) => String(line.id) === lineFilter))), requests);
  const waitingGroups = groupPlanningRequests(planningItems, requests);
  const progressedItems = orders.filter((order) => visible(order) &&
    (isScheduled(order) || ["active", "completed"].includes(String(order.status))) &&
    (!lineFilter || String(order.line_id) === lineFilter));
  const progressedGroups = groupPlanningRequests(progressedItems, requests);
  const scheduled = orders.filter((order) => ["planned", "active"].includes(String(order.status)) &&
    Boolean(order.line_id) && visible(order));
  const editing = orders.find((order) => String(order.id) === editingId);
  const selectedLine = lines.find((line) => String(line.id) === lineId);
  const availableLines = editing ? capableLines(editing, lines, centers, capabilities)
    .filter((line: Row) => !durationMs(editing, line, centers, capabilities).error) : [];
  const canEdit = can("orders", "edit");
  const editableItem = (order: Row) => canEdit && order.status === "planned" &&
    Number(order.produced_quantity || 0) === 0 && !order.planning_locked_at &&
    (!isScheduled(order) || Date.parse(String(order.start_time)) > Date.now());
  const canToggleLock = (order: Row) => canEdit && order.status === "planned" &&
    Number(order.produced_quantity || 0) === 0 && isScheduled(order) &&
    Date.parse(String(order.start_time)) > Date.now();
  const hasPlanningHistory = (order: Row) => Boolean(order.planning_ever_scheduled) || isScheduled(order);
  const lockInfo = (order: Row) => order.planning_locked_at
    ? [t("planningLocked"), order.planning_locked_by_name,
      formatTime(String(order.planning_locked_at), lang, zone)].filter(Boolean).join(" · ") : "";
  const canSeeResources = can("lines") && can("centers");
  const dragging = active.find((order) => String(order.id) === draggingId);
  const slotOrder = orders.find((order) => String(order.id) === slotSearch?.itemId);
  const chosenSlot = slotChoice === null ? null : slotSearch?.suggestions[slotChoice] || null;
  const productStyle = (order: Row) => {
    const tone = productColor(order.product_id, order.id);
    return { "--planning-product-bg": tone.surface, "--planning-product-ink": tone.ink,
      "--planning-product-edge": tone.edge } as React.CSSProperties;
  };
  const dropValidity = (order: Row | undefined, line: Row) => order &&
    editableItem(order) ? durationMs(order, line, centers, capabilities) :
    { error: order?.planning_locked_at ? "planningLockedMessage" : "planningAlreadyStarted" };
  const limited = (s.truncatedTables || []).some((table) =>
    ["production_orders", "production_requests", "production_lines", "work_centers", "work_center_capabilities"].includes(table));
  function dragReason(order: Row) {
    if (order.planning_locked_at) return "planningLockedMessage";
    if (order.status !== "planned") return planningBoardStatus(order);
    if (Number(order.produced_quantity || 0) > 0) return "planningAlreadyStarted";
    if (isScheduled(order) && Date.parse(String(order.start_time)) <= Date.now()) return "planningPastSchedule";
    const candidates = capableLines(order, lines, centers, capabilities);
    const checks = candidates.map((line: Row) => durationMs(order, line, centers, capabilities));
    if (checks[0]?.error === "planningMissingRate" && !["meter", "piece"].includes(String(order.unit)))
      return "planningLegacyUnit";
    return checks.some((check: { error?: string }) => !check.error) ? "" :
      checks[0]?.error || "planningIncompatibleLine";
  }
  const canDragItem = (order: Row) => editableItem(order) && !limited && canSeeResources &&
    !busy && !savingDropId && !dragReason(order);
  const zoomLevels = [
    { key: "planningZoomHalfDay", span: 12 * 60 * 60_000, tick: 30 * 60_000, snap: 30 * 60_000, minWidth: 1320 },
    { key: "planningZoomDay", span: 24 * 60 * 60_000, tick: 60 * 60_000, snap: 60 * 60_000, minWidth: 1320 },
    { key: "planningZoomThreeDays", span: 3 * 24 * 60 * 60_000, tick: 6 * 60 * 60_000, snap: 2 * 60 * 60_000, minWidth: 1100 },
    { key: "planningZoomWeek", span: 7 * 24 * 60 * 60_000, tick: 24 * 60 * 60_000, snap: 4 * 60 * 60_000, minWidth: 980 },
    { key: "planningZoomTwoWeeks", span: 14 * 24 * 60 * 60_000, tick: 2 * 24 * 60 * 60_000, snap: 12 * 60 * 60_000, minWidth: 980 },
    { key: "planningZoomMonth", span: 28 * 24 * 60 * 60_000, tick: 7 * 24 * 60 * 60_000, snap: 24 * 60 * 60_000, minWidth: 980 },
  ];
  const scale = zoomLevels[zoomIndex] || zoomLevels[1];
  const rangeStart = viewStart;
  const rangeEnd = rangeStart + scale.span;
  const visibleLines = lines.filter((line) => !line.archived && (!lineFilter || String(line.id) === lineFilter));
  const lineSchedules = new Map(visibleLines.map((line) => [String(line.id),
    sortedLineSchedule(line, orders, centers, capabilities, null, calendar, zone)]));
  const lineLoads = new Map(visibleLines.map((line) => [String(line.id),
    lineCapacity(lineSchedules.get(String(line.id)) || [], rangeStart, rangeEnd, calendar, zone)]));
  const visibleSlots = visibleLines.flatMap((line) => lineSchedules.get(String(line.id)) || [])
    .filter((slot) => slot.start < rangeEnd && (slot.finish === null || slot.finish > rangeStart));
  const plannedSlots = visibleSlots.filter((slot) => slot.order.status === "planned" && visible(slot.order));
  const riskOf = (slot: {order: Row; finish: number | null}) => Number.isFinite(slot.finish)
    ? deadlineStatus(slot.finish, requestById.get(String(slot.order.request_id))?.required_by)
    : "planningDeadlineUnknown";
  const visualState = (order: Row) => {
    if (['completed', 'cancelled'].includes(String(order.status))) return String(order.status);
    const due = requestById.get(String(order.request_id))?.required_by;
    const risk = deadlineStatus(Date.parse(String(order.expected_finish || '')), due);
    if (orderAttention(order) || Date.parse(String(due || '')) < Date.now() || risk === 'planningLate') return 'delayed';
    if (order.status === 'active') return 'active';
    if (risk === 'planningAtRisk') return 'risk';
    return isScheduled(order) ? 'scheduled' : 'waiting';
  };
  const summary = { waiting: planningItems.length, planned: plannedSlots.length,
    atRisk: plannedSlots.filter((slot) => riskOf(slot) === "planningAtRisk").length,
    late: plannedSlots.filter((slot) => riskOf(slot) === "planningLate").length };
  const formatQuantity = (value: number) => new Intl.NumberFormat(lang === "ar" ? "ar" : "en", {
    maximumFractionDigits: 1,
  }).format(value);
  const snapIncrement = scale.snap;
  const ticks = Array.from({ length: Math.floor(scale.span / scale.tick) + 1 }, (_, index) =>
    rangeStart + index * scale.tick);
  const tickLabel = (time: number) => new Intl.DateTimeFormat(lang === "ar" ? "ar" : "en", {
    timeZone: zone, ...(zoomIndex === 0
      ? { hour: "2-digit" as const, minute: "2-digit" as const, hourCycle: "h23" as const }
      : zoomIndex === 1 ? { hour: "numeric" as const, hourCycle: "h23" as const }
      : zoomIndex === 2 ? { month: "short" as const, day: "numeric" as const,
          hour: "numeric" as const, hourCycle: "h23" as const }
      : { month: "short" as const, day: "numeric" as const }),
  }).format(time);
  const position = (time: number) => Math.max(0, Math.min(100, (time - rangeStart) / (rangeEnd - rangeStart) * 100));
  const widthOf = (duration: number) => duration / (rangeEnd - rangeStart) * 100;
  const nowPosition = Date.now() >= rangeStart && Date.now() <= rangeEnd ? position(Date.now()) : null;
  const working = workingSegments(rangeStart, rangeEnd, calendar, zone);
  const closed = calendar ? (() => {
    const segments: { start: number; finish: number }[] = [];
    let cursor = rangeStart;
    for (const period of working) {
      if (period.start > cursor) segments.push({ start: cursor, finish: period.start });
      cursor = period.finish;
    }
    if (cursor < rangeEnd) segments.push({ start: cursor, finish: rangeEnd });
    return segments;
  })() : [];
  const selectedSchedule = selectedLine ? sortedLineSchedule(selectedLine, orders, centers, capabilities,
    editingId, calendar, zone) : [];
  const selectedDuration: any = editing && selectedLine ? durationMs(editing, selectedLine, centers, capabilities) : null;
  const proposedStart = (() => { try { return start ? Date.parse(localDateTimeToUtc(start, zone)) : NaN; }
    catch { return NaN; } })();
  const proposal: any = editing && selectedLine && Number.isFinite(proposedStart)
    ? proposeSchedule(editing, selectedLine, proposedStart, orders, centers, capabilities,
      Date.now(), calendar, zone) : null;
  const suggestedGaps: any[] = selectedDuration && !selectedDuration.error ?
    freeGaps(selectedSchedule, Math.max(Date.now(), rangeStart), rangeStart + 7 * 24 * 60 * 60_000).gaps
      ?.map((gap: { start: number; finish: number }) => ({ ...gap,
        slot: firstAvailable([], gap.start, selectedDuration.totalMs, gap.finish, calendar, zone) }))
      .filter((gap: { slot: { error?: string } }) => !gap.slot.error).slice(0, 6) || [] : [];

  useEffect(() => {
    if (editing) headingRef.current?.focus();
  }, [editingId, editing]);
  useEffect(() => {
    if (!editingId || !s.factory?.id) { setHistory([]); return; }
    const controller = new AbortController();
    setHistoryLoading(true);
    fetch("/api/planning-history?factory=" + encodeURIComponent(String(s.factory.id)) +
      "&item=" + encodeURIComponent(editingId), { signal: controller.signal })
      .then(async (response) => {
        if (!response.ok) throw new Error("history");
        return response.json();
      })
      .then((body) => setHistory(body.revisions || []))
      .catch(() => { if (!controller.signal.aborted) setHistory(null); })
      .finally(() => { if (!controller.signal.aborted) setHistoryLoading(false); });
    return () => controller.abort();
  }, [editingId, s.factory?.id]);
  useEffect(() => {
    if (pendingReason) reasonSelectRef.current?.focus();
  }, [pendingReason]);
  useEffect(() => {
    if (slotSearch) slotPanelRef.current?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [slotSearch]);
  useEffect(() => {
    if (!editing) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setEditingId(null);
        requestAnimationFrame(() => openerRef.current?.isConnected && openerRef.current.focus());
        return;
      }
      if (event.key !== "Tab") return;
      const controls = drawerRef.current?.querySelectorAll<HTMLElement>(
        "button:not([disabled]), select:not([disabled]), input:not([disabled])");
      if (!controls?.length) return;
      const first = controls[0]; const last = controls[controls.length - 1];
      if (event.shiftKey && (document.activeElement === first || document.activeElement === headingRef.current)) {
        event.preventDefault(); last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault(); first.focus();
      }
    };
    document.addEventListener("keydown", onKeyDown);
    return () => document.removeEventListener("keydown", onKeyDown);
  }, [editing]);
  // Direct panning: shift+wheel, trackpad horizontal scroll, or dragging the
  // empty timeline background. Pure view navigation — never a scheduling write.
  useEffect(() => {
    const container = timelineRef.current;
    if (!container) return;
    const onWheel = (event: WheelEvent) => {
      const delta = Math.abs(event.deltaX) > Math.abs(event.deltaY) ? event.deltaX
        : event.shiftKey ? event.deltaY : 0;
      if (!delta) return;
      event.preventDefault();
      setViewStart((current) => wheelViewStart(current, scale.span, container.clientWidth, delta));
    };
    container.addEventListener("wheel", onWheel, { passive: false });
    return () => container.removeEventListener("wheel", onWheel);
  }, [scale.span]);

  function beginPan(event: React.PointerEvent<HTMLDivElement>) {
    if (event.button !== 0 || draggingId) return;
    if (event.target instanceof Element &&
      event.target.closest("button, input, select, a, textarea")) return;
    panStateRef.current = { pointerId: event.pointerId, x: event.clientX,
      viewStart, width: event.currentTarget.clientWidth || 1 };
    try { event.currentTarget.setPointerCapture?.(event.pointerId); }
    catch { /* pointer already released (e.g. synthetic events) — panning still works */ }
    setPanning(true);
  }
  function movePan(event: React.PointerEvent<HTMLDivElement>) {
    const state = panStateRef.current;
    if (!state || event.pointerId !== state.pointerId) return;
    setViewStart(panViewStart(state.viewStart, scale.span, state.width, event.clientX - state.x));
  }
  function endPan(event: React.PointerEvent<HTMLDivElement>) {
    if (!panStateRef.current || event.pointerId !== panStateRef.current.pointerId) return;
    panStateRef.current = null;
    setPanning(false);
  }

  const productOf = (order: Row) => products.find((product) => String(product.id) === String(order.product_id));
  const historyLineName = (id: string | null | undefined) => {
    const line = lines.find((candidate) => String(candidate.id) === String(id));
    return line ? localName(line, lang) : "—";
  };
  const historyTime = (value: string) => formatLocalInput(value, zone).replace("T", " ");
  const unitOf = (order: Row) => t(order.unit === "meter" ? "meterShort" : order.unit === "piece" ? "pieceShort" : "legacyUnit");
  const amountOf = (order: Row) => `${Number(order.target_quantity).toLocaleString(lang)} ${unitOf(order)}`;
  const requestOf = (order: Row) => requestById.get(String(order.request_id));

  function openEditor(order: Row, proposedLine = String(order.line_id || ""), proposedTime?: number) {
    openerRef.current = document.activeElement instanceof HTMLButtonElement ? document.activeElement : null;
    setEditingId(String(order.id));
    setLineId(proposedLine);
    const line = lines.find((candidate) => String(candidate.id) === proposedLine);
    const duration: any = line ? durationMs(order, line, centers, capabilities) : null;
    const next: any = line && duration && !duration.error
      ? firstAvailable(sortedLineSchedule(line, orders, centers, capabilities, String(order.id), calendar, zone),
        Math.ceil(Date.now() / 900_000) * 900_000, duration.totalMs,
        Date.now() + 365 * 24 * 60 * 60_000, calendar, zone) : null;
    const initial = proposedTime ?? (order.start_time ? Date.parse(String(order.start_time)) : next?.start);
    setStart(Number.isFinite(initial) ? formatLocalInput(new Date(initial).toISOString(), zone) : "");
    setError("");
  }
  function askReason(pending: PendingReason) {
    setReasonCode(""); setReasonNote(""); setPendingReason(pending); setError("");
  }
  function cancelReason() {
    if (pendingReason?.source === "drop") {
      setOptimistic(null); setSavingDropId(null); setSettlingId(null);
    }
    setPendingReason(null); setError("");
  }
  async function submitReason(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!pendingReason) return;
    if (!reasonCodes.includes(reasonCode as typeof reasonCodes[number]) ||
      (reasonCode === "other" && !reasonNote.trim())) {
      setError("planningReasonRequired"); return;
    }
    const pending = pendingReason;
    setBusy(true); setError("");
    try {
      await command("revise_product_plan", { factory: s.factory?.id, item: pending.item,
        target_line: pending.target_line, planned_start: pending.planned_start,
        reason_code: reasonCode, reason_note: reasonNote.trim() });
      setPendingReason(null);
      if (pending.source !== "drop") closeEditor();
    } catch (cause) {
      setError(cause instanceof Error && cause.message ? cause.message : "planningSaveFailed");
      setPendingReason(null);
      if (pending.source === "drop") {
        setRejectedId(pending.item);
        setTimeout(() => setRejectedId(null), 450);
      }
    } finally {
      setBusy(false);
      if (pending.source === "drop") {
        setOptimistic(null); setSavingDropId(null);
        setTimeout(() => setSettlingId(null), 450);
      }
    }
  }
  async function toggleLock() {
    if (!editing || !canToggleLock(editing)) return;
    setBusy(true); setError("");
    try { await command("set_plan_lock", { factory: s.factory?.id, item: editing.id,
      locked: !editing.planning_locked_at }); }
    catch (cause) { setError(cause instanceof Error ? cause.message : "planningSaveFailed"); }
    finally { setBusy(false); }
  }
  function chooseLine(nextLineId: string) {
    setLineId(nextLineId);
    const line = lines.find((candidate) => String(candidate.id) === nextLineId);
    if (!editing || !line) { setStart(""); return; }
    const duration: any = durationMs(editing, line, centers, capabilities);
    if (duration.error) { setStart(""); setError(duration.error); return; }
    const slot: any = firstAvailable(sortedLineSchedule(line, orders, centers, capabilities,
      String(editing.id), calendar, zone),
      Math.ceil(Date.now() / 900_000) * 900_000, duration.totalMs,
      Date.now() + 365 * 24 * 60 * 60_000, calendar, zone);
    setStart(slot.start ? formatLocalInput(new Date(slot.start).toISOString(), zone) : "");
    setError(slot.error || "");
  }
  function previewAt(event: React.DragEvent<HTMLDivElement>, line: Row, order: Row) {
    const rect = event.currentTarget.getBoundingClientRect();
    const raw = rangeStart + Math.max(0, Math.min(0.999, (event.clientX - rect.left) / rect.width)) *
      (rangeEnd - rangeStart);
    return previewPlacement(order, line, raw, orders, centers, capabilities, {
      from: rangeStart, until: rangeEnd, increment: snapIncrement, calendar, zone,
    });
  }
  async function dropItem(event: React.DragEvent<HTMLDivElement>, line: Row) {
    event.preventDefault();
    draggingRef.current = null;
    setDraggingId(null); setHoverPreview(null);
    const id = event.dataTransfer.getData("text/plain");
    const order = active.find((candidate) => String(candidate.id) === id);
    if (!order) return;
    const validity: any = dropValidity(order, line);
    if (validity.error) { setError(validity.error); setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450); return; }
    const placement: any = previewAt(event, line, order);
    if (placement.error) { setError(placement.error); setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450); return; }
    const startTime = new Date(placement.start).toISOString();
    if (isScheduled(order) && String(order.line_id) === String(line.id) &&
      Date.parse(String(order.start_time)) === placement.start) return;
    setError(""); setSavingDropId(id); setSettlingId(id);
    setOptimistic({ id, line_id: String(line.id), start_time: startTime,
      expected_finish: new Date(placement.finish).toISOString() });
    if (hasPlanningHistory(order)) {
      askReason({ source: "drop", item: id, target_line: String(line.id),
        planned_start: startTime });
      return;
    }
    try {
      await command("plan_product_item", { factory: s.factory?.id, item: order.id,
        target_line: line.id, planned_start: startTime });
    } catch (cause) {
      setError(cause instanceof Error && cause.message ? cause.message : "planningSaveFailed");
      setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450);
    } finally {
      setOptimistic(null); setSavingDropId(null);
      setTimeout(() => setSettlingId(null), 450);
    }
  }
  function closeEditor() {
    setEditingId(null);
    requestAnimationFrame(() => openerRef.current?.isConnected && openerRef.current.focus());
  }
  function finishDrag(id: string) {
    if (lastHoverRef.current?.itemId === id && lastHoverRef.current.error) {
      setError(lastHoverRef.current.error);
      setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450);
    }
    lastHoverRef.current = null;
    draggingRef.current = null;
    setDraggingId(null); setHoverPreview(null);
  }

  async function save(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (editing && !editableItem(editing)) {
      setError(editing.planning_locked_at ? "planningLockedMessage" : "planningAlreadyStarted");
      return;
    }
    if (!editing || !selectedLine || !availableLines.some((line: Row) => line.id === selectedLine.id) || !start) {
      setError("planningInvalidSelection"); return;
    }
    let utc: string;
    try { utc = localDateTimeToUtc(start, zone); }
    catch { setError("planningInvalidStart"); return; }
    if (!utc || !Number.isFinite(Date.parse(utc))) { setError("planningInvalidStart"); return; }
    const check: any = proposeSchedule(editing, selectedLine, Date.parse(utc), orders, centers, capabilities,
      Date.now(), calendar, zone);
    if (check.error) { setError(check.error); return; }
    if (hasPlanningHistory(editing) && (!isScheduled(editing) ||
      String(editing.line_id) !== String(selectedLine.id) ||
      Date.parse(String(editing.start_time)) !== check.start ||
      Date.parse(String(editing.expected_finish)) !== check.finish)) {
      askReason({ source: "save", item: String(editing.id), target_line: String(selectedLine.id),
        planned_start: utc });
      return;
    }
    setBusy(true); setError("");
    try {
      await command("plan_product_item", {
        factory: s.factory?.id, item: editing.id, target_line: selectedLine.id,
        planned_start: utc,
      });
      closeEditor();
    } catch (cause) { setError(cause instanceof Error ? cause.message : "planningSaveFailed"); }
    finally { setBusy(false); }
  }
  async function unschedule() {
    if (!editing) return;
    if (!editableItem(editing)) {
      setError(editing.planning_locked_at ? "planningLockedMessage" : "planningAlreadyStarted");
      return;
    }
    askReason({ source: "unschedule", item: String(editing.id), target_line: null, planned_start: null });
  }

  function findSlots(order: Row) {
    const now = Date.now();
    const result = suggestPlanningSlots(order, requestOf(order), lines, orders, centers, capabilities,
      { now: Math.ceil(now / 900_000) * 900_000, horizonDays: 28, limit: 3, calendar, zone });
    setSlotSearch({ itemId: String(order.id), ...result });
    setSlotChoice(null);
    setError("");
  }

  async function confirmSlot() {
    if (!slotOrder || !chosenSlot || busy || limited || !canSeeResources || !editableItem(slotOrder)) return;
    const line = lines.find((candidate) => String(candidate.id) === chosenSlot.lineId);
    if (!line || !capableLines(slotOrder, lines, centers, capabilities).some((candidate: Row) =>
      String(candidate.id) === chosenSlot.lineId)) { setError("planningInvalidSelection"); return; }
    const check: any = proposeSchedule(slotOrder, line, chosenSlot.start, orders, centers, capabilities,
      Date.now(), calendar, zone);
    if (check.error || check.finish !== chosenSlot.finish || check.start !== chosenSlot.start) {
      setError(check.error || "planningSlotChanged"); return;
    }
    const plannedStart = new Date(chosenSlot.start).toISOString();
    if (hasPlanningHistory(slotOrder)) {
      askReason({ source: "save", item: String(slotOrder.id), target_line: chosenSlot.lineId,
        planned_start: plannedStart });
      return;
    }
    setBusy(true); setError("");
    try {
      await command("plan_product_item", { factory: s.factory?.id, item: slotOrder.id,
        target_line: chosenSlot.lineId, planned_start: plannedStart });
      setSlotSearch(null); setSlotChoice(null);
    } catch (cause) { setError(cause instanceof Error ? cause.message : "planningSaveFailed"); }
    finally { setBusy(false); }
  }

  function itemRow(order: Row, section: "waiting" | "progressed", mobile = false) {
    const canDrag = canDragItem(order);
    const blockedReason = canEdit && canSeeResources && order.status === "planned" ? dragReason(order) : "";
    return <div className="planning-product-entry" key={String(order.id)}><button type="button" className={(mobile ? 'planning-mobile-product ' : '') + "planning-product-card" +
      (draggingId === String(order.id) ? " planning-product-dragging" : "") +
      (rejectedId === String(order.id) ? " planning-product-rejected" : "") +
      (savingDropId === String(order.id) ? " planning-product-saving" : "")}
      onClick={() => openEditor(order)}
      title={lockInfo(order) || (blockedReason ? t(blockedReason) : undefined)}
      style={productStyle(order)} data-state={visualState(order)} disabled={Boolean(savingDropId) || !can("orders", "view")}
      draggable={canDrag}
      onPointerDown={() => { if (order.planning_locked_at) setError("planningLockedMessage"); }}
      onDragStart={(event) => { if (!canDrag) { event.preventDefault(); return; }
        event.dataTransfer.setData("text/plain", String(order.id));
        event.dataTransfer.effectAllowed = "move"; draggingRef.current = String(order.id);
        lastHoverRef.current = null;
        setDraggingId(String(order.id)); setError(""); }}
      onDragEnd={() => finishDrag(String(order.id))}
      aria-label={`${localName(productOf(order), lang)} · ${amountOf(order)} · ${t(planningBoardStatus(order))} · ${String(requestOf(order)?.name || requestOf(order)?.code || "")}`}>
      <strong dir="auto"><ProductIdentity productId={order.product_id} productItemId={order.id}>
        {localName(productOf(order), lang)}</ProductIdentity></strong>
      <span>{amountOf(order)}</span>
      <small className="planning-product-state" data-state={order.status === 'active' ? 'active' : isScheduled(order) ? 'scheduled' : 'waiting'}>{order.planning_locked_at &&
        <span className="planning-lock-mark" aria-label={t("planningLocked")}>🔒 </span>}
        {t(planningBoardStatus(order))}</small>
      {['delayed', 'risk'].includes(visualState(order)) && <small className="planning-attention-label" data-state={visualState(order)}>! {t(visualState(order) === 'delayed' ? 'delayed' : 'planningAtRisk')}</small>}
      {mobile && <small className="planning-product-state"><bdi dir="ltr">{String(requestOf(order)?.code || order.code || '')}</bdi></small>}
      {Boolean(order.line_id && order.start_time) && <span className="planning-product-schedule">
        <bdi dir="auto">{localName(lines.find(line => line.id === order.line_id), lang)}</bdi>
        <span>{t('executionPlannedStart')}: {formatTime(order.start_time, lang, zone)}</span>
        {order.expected_finish && <span>{t('executionPlannedFinish')}: {formatTime(order.expected_finish, lang, zone)}</span>}
      </span>}
      {order.status === 'active' && <span className="planning-product-schedule">{t('recordingGoodSoFar')}: {productionProgress(order).good.toLocaleString(lang)} {unitOf(order)}</span>}
      {blockedReason && <small className="planning-drag-reason">{t(blockedReason)}</small>}
    </button>{section === "waiting" && canDrag &&
      <button type="button" className="planning-find-slot" disabled={busy || Boolean(savingDropId)}
        onClick={() => findSlots(order)}>{t("planningFindSlot")}</button>}</div>;
  }

  function requestCard({ request, items }: { request: Row | null; items: Row[] }, section: "waiting" | "progressed") {
    const key = String(request?.id || items[0].request_id || items[0].id);
    const total = orders.filter((item) => String(item.request_id) === key).length || items.length;
    const requestRisk = items.filter((item) => item.status === "planned" && isScheduled(item))
      .map((item) => lineSchedules.get(String(item.line_id))?.find((slot: {order: Row}) => String(slot.order.id) === String(item.id)))
      .filter((slot): slot is NonNullable<typeof slot> => Boolean(slot))
      .map(riskOf);
    const risk = requestRisk.includes("planningLate") ? "planningLate" :
      requestRisk.includes("planningAtRisk") ? "planningAtRisk" : null;
    const overdue = items.some(item => !['completed', 'cancelled'].includes(String(item.status))) && Date.parse(String(request?.required_by || '')) < Date.now();
    return <article className="planning-request-card" role="listitem" data-request-id={key} data-state={overdue ? 'delayed' : risk === 'planningLate' ? 'delayed' : risk === 'planningAtRisk' ? 'risk' : section === 'waiting' ? 'waiting' : requestPresentation(request || {}, items).tone} key={key}>
      <header className="planning-request-head"><div><small><bdi dir="ltr">{String(request?.code || items[0].code)}</bdi></small>
        {section !== 'waiting' && <h4 dir="auto">{String(request?.name || request?.code || items[0].code)}</h4>}</div>
        <span className={"planning-request-priority planning-priority-" + String(request?.priority || "normal")}>
          {request?.priority === "unspecified" ? t("notSpecified") : t(`priority_${request?.priority || "normal"}`)}</span></header>
      <div className="planning-request-meta">
        {(request?.required_by || section === 'waiting') && <span>{t("requiredBy")}: {request?.required_by ? formatTime(request.required_by, lang, zone) : t('notSpecified')}</span>}
        {overdue && <span className="planning-attention-label" data-state="delayed">! {t('requestsDeadlinePassed')}</span>}
        {risk && <span className={"planning-request-risk " + risk}>{t(risk)}</span>}
        <span>{section === 'waiting' ? `${items.length} ${t('planningWaitingCount')}` : `${items.length} / ${total} ${t("planningProgressedCount")}`}</span></div>
      <div className="planning-request-items">{items.map((item) => itemRow(item, section))}</div>
    </article>;
  }

  function changeZoom(next: number) {
    const bounded = Math.max(0, Math.min(zoomLevels.length - 1, next));
    setViewStart((current) => zoomViewStart(current, scale.span, zoomLevels[bounded].span));
    setZoomIndex(bounded);
  }

  return <section className="planning-page ops-workbench" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    <p className="ops-page-subtitle">{t('planningOperationalSubtitle')}</p>
    <div className="planning-filters">
      <label>{t("line")} <select value={lineFilter} onChange={(event) => setLineFilter(event.target.value)}>
        <option value="">{t("all")}</option>{lines.filter((line) => !line.archived).map((line) =>
          <option key={String(line.id)} value={String(line.id)}>{localName(line, lang)}</option>)}
      </select></label>
      <label>{t("product")} <select value={productFilter} onChange={(event) => setProductFilter(event.target.value)}>
        <option value="">{t("all")}</option>{products.filter((product) => !product.archived).map((product) =>
          <option key={String(product.id)} value={String(product.id)}>{localName(product, lang)}</option>)}
      </select></label>
      <label>{t("priority")} <select value={priorityFilter} onChange={(event) => setPriorityFilter(event.target.value)}>
        <option value="">{t("all")}</option>{["urgent", "high", "normal", "low"].map((priority) =>
          <option key={priority} value={priority}>{t(`priority_${priority}`)}</option>)}
      </select></label>
    </div>
    {limited &&
      <p className="planning-warning-banner" role="status">{t("planningSnapshotLimited")}</p>}
    {!canSeeResources && <p className="planning-warning-banner" role="status">{t("planningResourcesPermission")}</p>}
    {error && !editing && <p className="planning-warning-banner" role="alert">{t(error)}</p>}
    <div className="planning-workspace">
    <section className="planning-section planning-requests-waiting" aria-labelledby="planning-needs-title">
      <header><h3 id="planning-needs-title">{t("planningWaitingTitle")} <span>{waitingGroups.length}</span></h3>
        </header>
      {waitingGroups.length ? <div className="planning-list" role="list">{waitingGroups.map((group) => requestCard(group, "waiting"))}</div> :
        <p className="planning-empty">{t("planningQueueEmpty")}</p>}
    </section>
    <section className="planning-section planning-gantt" aria-labelledby="planning-scheduled-title">
      <header><h3 id="planning-scheduled-title">{t("scheduled")} <span>{scheduled.length}</span></h3>
        </header>
    <section className="planning-summary" aria-label={t("planningSummary")}>
      <dl>
        <div><dt>{t("planningSummaryWaiting")}</dt><dd>{formatQuantity(summary.waiting)}</dd></div>
        <div><dt>{t("planningSummaryPlanned")}</dt><dd>{formatQuantity(summary.planned)}</dd></div>
        <div><dt>{t("planningSummaryAtRisk")}</dt><dd>{formatQuantity(summary.atRisk)}</dd></div>
        <div><dt>{t("planningSummaryLate")}</dt><dd>{formatQuantity(summary.late)}</dd></div>
      </dl>
      <small title={t('planningSummaryScope')}>{t('planningVisibleScope')}</small>
    </section>
      {slotSearch && slotOrder && <div className="planning-slot-panel" ref={slotPanelRef} role="region"
        aria-label={t("planningSlotSuggestions")}>
        <div className="planning-slot-heading"><div><strong>{t("planningSlotSuggestions")}</strong>
          <span dir="auto">{localName(productOf(slotOrder), lang)} · {amountOf(slotOrder)}</span></div>
          <button type="button" aria-label={t("close")} onClick={() => {
            setSlotSearch(null); setSlotChoice(null); setError(""); }}>×</button></div>
        {slotSearch.suggestions.length ? <div className="planning-slot-list">
          {slotSearch.suggestions.map((slot, index) => {
            const line = lines.find((candidate) => String(candidate.id) === slot.lineId);
            return <article className={"planning-slot-option" + (slotChoice === index ? " planning-slot-selected" : "")}
              key={slot.lineId + ":" + slot.start}>
              <div className="planning-slot-main"><strong dir="auto">{localName(line, lang)}</strong>
                <span className={slot.deadline === "planningLate" ? "planning-warning" : ""}>{t(slot.deadline)}</span></div>
              <div className="planning-slot-times" dir="ltr">
                <time dateTime={new Date(slot.start).toISOString()}>{formatTime(new Date(slot.start).toISOString(), lang, zone)}</time>
                <span aria-hidden="true">→</span>
                <time dateTime={new Date(slot.finish).toISOString()}>{formatTime(new Date(slot.finish).toISOString(), lang, zone)}</time></div>
              <div className="planning-slot-facts">
                <span>{t("planningRate")}: {formatQuantity(slot.rate)} {unitOf(slotOrder)}/{t("planningHour")}</span>
                <span>{t("planningSlotSetup")}: {formatDuration(Math.ceil(slot.setupMs / 60_000), lang)}</span>
                <span>{t("planningSlotProduction")}: {formatDuration(Math.ceil(slot.productionMs / 60_000), lang)}</span>
                <span>{t("planningSlotTotal")}: {formatDuration(Math.ceil(slot.totalMs / 60_000), lang)}</span>
                <span>{t("planningSlotLoad")}: {slot.load.percent === null ? t("planningLoadNoCapacity") :
                  `${formatQuantity(slot.load.percent)}%`}{slot.load.incomplete ? " *" : ""}</span></div>
              <button type="button" onClick={() => { setSlotChoice(index);
                setViewStart(Math.round(slot.start - scale.span * 0.18)); setError(""); }}>
                {t("planningPreviewSlot")}</button>
            </article>;
          })}</div> : <p className="planning-slot-empty">{t(slotSearch.reason || "planningSlotNone")}
          {slotSearch.reason === "planningSlotNone" && ` (${slotSearch.horizonDays} ${t("planningDays")})`}
          {" "}{t("planningSlotManualFallback")}</p>}
        {chosenSlot && <div className="planning-slot-confirm" role="status">
          <span>{t("planningSlotPreviewHelp")}</span>
          <button type="button" className="primary" disabled={busy || !editableItem(slotOrder)}
            onClick={() => void confirmSlot()}>{t("planningConfirmSlot")}</button></div>}
        {error && <p className="planning-warning" role="alert">{t(error)}</p>}
      </div>}
      <div className="planning-board-toolbar">
        <label className="planning-window-start"><span>{t("planningVisibleStart")} ({zone})</span>
          <input type="datetime-local" dir="ltr" value={formatLocalInput(new Date(viewStart).toISOString(), zone)}
            onChange={(event) => { if (!event.target.value) return;
              try { setViewStart(Date.parse(localDateTimeToUtc(event.target.value, zone))); }
              catch { /* keep the last valid window start during an incomplete edit */ }
            }} /></label>
        <div className="planning-window-end"><span>{t("planningVisibleEnd")}</span>
          <time dateTime={new Date(rangeEnd).toISOString()} dir="ltr">
            {formatTime(new Date(rangeEnd).toISOString(), lang, zone)}</time></div>
        <div className="planning-zoom-control">
          <label htmlFor="planning-zoom-slider">{t("planningZoom")}</label>
          <input id="planning-zoom-slider" type="range" min="0" max={zoomLevels.length - 1} step="1"
            value={zoomIndex} onChange={(event) => changeZoom(Number(event.target.value))}
            aria-valuetext={t(scale.key)} />
          <strong>{t(scale.key)}</strong>
        </div>
      </div>
      <div ref={timelineRef}
        className={"planning-timeline-scroll" + (panning ? " planning-panning" : "")}
        dir="ltr"
        onPointerDown={beginPan} onPointerMove={movePan}
        onPointerUp={endPan} onPointerCancel={endPan}>
        <div className="planning-timeline" dir="ltr" style={{ minWidth: scale.minWidth }}>
          <div className="planning-axis"><span className="planning-line-label">{t("line")}</span>
            <div className="planning-axis-track">{ticks.map((tick, index) =>
              <span key={tick} style={{ left: position(tick) + "%" }}>{index === ticks.length - 1 ? "" : tickLabel(tick)}</span>)}</div>
          </div>
          {visibleLines.map((line) => {
            const schedule = lineSchedules.get(String(line.id)) || [];
            const load = lineLoads.get(String(line.id));
            const gaps = freeGaps(draggingId ? sortedLineSchedule(line, orders, centers, capabilities,
              draggingId, calendar, zone) : schedule,
              rangeStart, rangeEnd).gaps || [];
            const conflicts = overlappingItems(schedule);
            const trackEnds: number[] = [];
            const stacked = schedule.map((slot: {order: Row; start: number; finish: number | null}) => {
              let track = trackEnds.findIndex((finish) => finish <= slot.start);
              if (track < 0) track = trackEnds.length;
              trackEnds[track] = slot.finish ?? Infinity;
              return { ...slot, track };
            });
            const dropState: any = dragging ? dropValidity(dragging, line) : null;
            const linePreview = hoverPreview?.lineId === String(line.id) ? hoverPreview : null;
            const dropClass = dragging ? dropState?.error || linePreview?.error ?
              " planning-drop-invalid" : " planning-drop-valid" : "";
            return <div className={"planning-lane" + dropClass +
              (linePreview ? " planning-drop-hover" : "")} key={String(line.id)}>
              <strong className="planning-line-label" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
                <span className="planning-line-name">{localName(line, lang)}</span>
                {line.paused_at && <small>{t('planningLinePaused')}</small>}
                {lineExecutionQueue(orders, line.id).current?.status === 'active' && <small className="planning-current-label">● {t('active')}</small>}
                {([['executionCurrentReady', lineExecutionQueue(orders, line.id).current],
                  ['executionNext', lineExecutionQueue(orders, line.id).next]] as const).map(([label, item]) => item &&
                  <small className="planning-line-job" key={label}><span>{t(label)}</span>
                    <bdi dir="auto"><ProductIdentity productId={item.product_id} productItemId={item.id}>{localName(productOf(item), lang)}</ProductIdentity></bdi>
                    <bdi dir="ltr">{String(requestOf(item)?.code || item.code)}</bdi></small>)}
                {load && <><span className="planning-line-load" dir="ltr"
                  title={load.incomplete ? t("planningLoadIncomplete") : t("planningLoadDetail")}>{load.percent === null
                    ? t("planningLoadNoCapacity") : `${formatQuantity(load.percent)}%`} · {formatDuration(load.bookedMinutes, lang)} / {formatDuration(load.availableMinutes, lang)}{load.incomplete ? " *" : ""}</span>
                  <span className="planning-load-track" aria-hidden="true"><span style={{ width: Math.min(100,
                    Math.max(0, load.percent || 0)) + "%" }} /></span></>}
                {dragging && <small className={dropState?.error || linePreview?.error ? "planning-warning" : "planning-drop-hint"}>
                  {dropState?.error || linePreview?.error ? t(dropState?.error || linePreview?.error || "") :
                    linePreview?.durationMs ? `${formatDuration(Math.ceil(linePreview.durationMs / 60_000), lang)} · ${linePreview.rate} ${unitOf(dragging)}/${t("planningHour")}` :
                    formatDuration(Math.ceil(dropState.totalMs / 60_000), lang)}</small>}
                {linePreview && !linePreview.error && linePreview.requestedStart !== linePreview.start &&
                  <small className="planning-drop-hint">{t("planningSnappedStart")}: {formatTime(new Date(linePreview.start).toISOString(), lang, zone)}</small>}
                {conflicts.size > 0 && <small className="planning-warning">{t("planningOverlap")}</small>}</strong>
              <div className="planning-lane-track" onDragOver={(event) => {
                  const draggedOrder = active.find((candidate) =>
                    String(candidate.id) === (draggingRef.current || draggingId));
                  if (!canEdit || !draggedOrder) return;
                  event.preventDefault();
                  const result: any = previewAt(event, line, draggedOrder);
                  event.dataTransfer.dropEffect = result.error ? "none" : "move";
                   const next = { itemId: String(draggedOrder.id), lineId: String(line.id),
                     start: result.start, finish: result.finish, durationMs: result.durationMs,
                     productionMs: result.productionMs, setupMs: result.setupMs,
                     requestedStart: result.requestedStart,
                     rate: result.rate, error: result.error };
                   lastHoverRef.current = { itemId: next.itemId, error: next.error };
                  setHoverPreview((previous) => previous?.itemId === next.itemId &&
                    previous.lineId === next.lineId && previous.start === next.start &&
                    previous.error === next.error ? previous : next);
                }}
                onDragLeave={(event) => { if (!event.currentTarget.contains(event.relatedTarget as Node)) setHoverPreview(null); }}
                onDrop={(event) => { if (canEdit && !limited && canSeeResources && !savingDropId) void dropItem(event, line); }}
                style={{ height: Math.max(76, 12 + trackEnds.length * 43) }}>
                {closed.map((period) => <i className="planning-closed-time" key={period.start}
                  style={{ left: position(period.start) + "%", width: widthOf(period.finish - period.start) + "%" }}
                  title={t("planningClosedTime")} />)}
                {ticks.slice(1, -1).map((tick) => <i className="planning-gridline" key={tick}
                  style={{ left: position(tick) + "%" }} />)}
                {gaps.map((gap: { start: number; finish: number }) =>
                  <span className={"planning-free-gap" + (dragging && !dropState?.error &&
                    !firstAvailable([], Math.max(gap.start, Math.ceil(Date.now() / snapIncrement) * snapIncrement),
                      dropState.totalMs, gap.finish, calendar, zone).error ? " planning-gap-fits" : "")} key={gap.start}
                    style={{ left: position(gap.start) + "%", width: position(gap.finish) - position(gap.start) + "%" }}
                    title={t("planningFreeGap") + " · " + formatTime(new Date(gap.start).toISOString(), lang, zone) +
                      " – " + formatTime(new Date(gap.finish).toISOString(), lang, zone)} />)}
                {stacked.map((slot: {order: Row; start: number; finish: number | null; track: number}) => {
                  const order = slot.order as Row;
                  if (slot.start >= rangeEnd || (slot.finish !== null && slot.finish <= rangeStart)) return null;
                  const finish = slot.finish ?? Math.min(rangeEnd, slot.start + 60 * 60_000);
                  const blockWidth = Math.max(0.3, widthOf(finish - Math.max(slot.start, rangeStart)));
                  const request = requestOf(order);
                  const dueState = riskOf(slot);
                  const hasRisk = dueState === "planningLate" || dueState === "planningAtRisk";
                  const breakdown: any = durationMs(order, line, centers, capabilities);
                  const setupFinish = !breakdown.error && breakdown.setupMs > 0 && slot.finish !== null
                    ? finishAfterWorkingMs(slot.start, breakdown.setupMs, calendar, zone) : slot.start;
                  return <button type="button" key={String(order.id)}
                    data-state={conflicts.has(String(order.id)) ? 'blocked' : visualState(order)}
                    className={"planning-gantt-block" + (dueState === "planningLate" ? " planning-gantt-late" :
                      dueState === "planningAtRisk" ? " planning-gantt-risk" : "") +
                      (hasRisk ? " planning-has-risk" : "") +
                      (order.status === 'active' ? ' planning-gantt-active' : '') +
                      (order.planning_locked_at ? ' planning-gantt-locked' : '') +
                      (conflicts.has(String(order.id)) ? " planning-gantt-conflict" : "") +
                      (blockWidth < 6 ? " planning-gantt-compact" : "") +
                      (settlingId === String(order.id) ? " planning-gantt-settling" : "") +
                      (savingDropId === String(order.id) ? " planning-gantt-pending" : "")}
                    style={{ top: 5 + slot.track * 43, left: position(slot.start) + "%",
                      width: blockWidth + "%",
                      ...productStyle(order) }}
                    disabled={!can("orders", "view")}
                    draggable={canDragItem(order)}
                    onPointerDown={() => { if (order.planning_locked_at) setError("planningLockedMessage"); }}
                    onDragStart={(event) => { if (!canDragItem(order)) { event.preventDefault(); return; }
                      event.dataTransfer.setData("text/plain", String(order.id));
                      event.dataTransfer.effectAllowed = "move"; draggingRef.current = String(order.id);
                      lastHoverRef.current = null;
                      setDraggingId(String(order.id)); setError(""); }}
                    onDragEnd={() => finishDrag(String(order.id))}
                    onClick={() => openEditor(order)}
                    title={String(request?.code || order.code) + " · " + localName(productOf(order), lang) +
                      (!breakdown.error ? " · " + t("planningSetupDuration") + ": " + formatDuration(breakdown.setupMinutes, lang) +
                        " · " + t("planningProductionDuration") + ": " + formatDuration(Math.ceil(breakdown.productionMs / 60_000), lang) +
                        " · " + t("planningTotalWorking") + ": " + formatDuration(Math.ceil(breakdown.totalMs / 60_000), lang) : "") +
                      " · " + formatTime(new Date(slot.start).toISOString(), lang, zone) +
                      " – " + (slot.finish ? formatTime(new Date(slot.finish).toISOString(), lang, zone) : t("planningUnknownFinish")) +
                      (request?.required_by ? ' · ' + t('requiredBy') + ': ' + formatTime(request.required_by, lang, zone) : '') +
                      (order.planning_locked_at ? " · " + lockInfo(order) : "")}
                    aria-label={String(request?.code || order.code) + " · " + localName(productOf(order), lang) +
                      ' · ' + amountOf(order) + ' · ' + t('executionPlannedStart') + ': ' + formatTime(order.start_time, lang, zone) +
                      ' · ' + t('executionPlannedFinish') + ': ' + formatTime(order.expected_finish, lang, zone) +
                      (visualState(order) === 'delayed' ? ' · ' + t('delayed') : '') +
                      (conflicts.has(String(order.id)) ? ' · ' + t('planningOverlap') : '') +
                      (hasRisk ? " · " + t(dueState) : "") +
                      (order.planning_locked_at ? " · " + t("planningLocked") : "")}>
                    {setupFinish > slot.start && setupFinish < finish &&
                      <i className="planning-setup-segment" style={{ width: Math.min(100,
                        (setupFinish - slot.start) / (finish - slot.start) * 100) + "%" }} />}
                    <strong>{localName(productOf(order), lang)}</strong>
                    {order.planning_locked_at && <span className="planning-lock-mark" aria-hidden="true">🔒</span>}
                    {hasRisk && <span className={"planning-risk-mark " + dueState} aria-hidden="true"
                      title={t(dueState)}>!</span>}
                    <small><bdi dir="ltr">{String(request?.code || order.code)}</bdi>
                      {' · '}{amountOf(order)}{order.status === 'active' ? ' · ' + t('active') : ''}
                      {visualState(order) === 'delayed' ? ' · ! ' + t('delayed') : visualState(order) === 'risk' ? ' · ! ' + t('planningAtRisk') : ''}
                      {slot.finish === null ? " · ?" : ""}{["urgent", "high"].includes(String(request?.priority)) ?
                        " · " + t(`priority_${request?.priority}`) : ""}</small>
                  </button>;
                })}
                {linePreview && dragging && Number.isFinite(linePreview.start) && linePreview.durationMs &&
                  <span className={"planning-drag-ghost" + (linePreview.error ? " planning-drag-ghost-invalid" : "")}
                    style={{ left: position(linePreview.start) + "%", width: widthOf(linePreview.finish - linePreview.start) + "%",
                      ...productStyle(dragging) }}
                    aria-hidden="true">{linePreview.setupMs && <i className="planning-setup-segment"
                      style={{ width: Math.min(100, (finishAfterWorkingMs(linePreview.start, linePreview.setupMs,
                        calendar, zone) - linePreview.start) / (linePreview.finish - linePreview.start) * 100) + "%" }} />}
                    <span dir="auto">{localName(productOf(dragging), lang)}</span></span>}
                {chosenSlot && slotOrder && chosenSlot.lineId === String(line.id) &&
                  chosenSlot.start < rangeEnd && chosenSlot.finish > rangeStart &&
                  <span className="planning-drag-ghost planning-slot-ghost"
                    style={{ left: position(chosenSlot.start) + "%",
                      width: widthOf(chosenSlot.finish - chosenSlot.start) + "%", ...productStyle(slotOrder) }}
                    aria-label={t("planningSlotPreviewHelp")}>
                    {chosenSlot.setupMs > 0 && <i className="planning-setup-segment"
                      style={{ width: Math.min(100, (finishAfterWorkingMs(chosenSlot.start,
                        chosenSlot.setupMs, calendar, zone) - chosenSlot.start) /
                        (chosenSlot.finish - chosenSlot.start) * 100) + "%" }} />}
                    <span dir="auto">{localName(productOf(slotOrder), lang)}</span></span>}
                {nowPosition !== null && <i className="planning-now" style={{ left: nowPosition + "%" }}
                  title={t("planningNow")} />}
              </div>
            </div>;
          })}
        </div>
      </div>
      <div className="planning-mobile-lines" aria-label={t('planningLineSchedule')}>
        {visibleLines.map(line => {
          const queue = lineExecutionQueue(orders, line.id);
          const slots = lineSchedules.get(String(line.id)) || [];
          const additional = slots.filter((slot: { order: Row }) => ![queue.current?.id, queue.next?.id].includes(slot.order.id));
          return <article className="planning-mobile-line" key={String(line.id)}>
            <header><h4 dir="auto">{localName(line, lang)}</h4>
              {line.paused_at && <span>{t('planningLinePaused')}</span>}</header>
            {([['executionCurrentReady', queue.current], ['executionNext', queue.next]] as const).map(([label, item]) => item &&
              <div className="planning-mobile-job" key={label}><small>{t(label)}</small>
                {itemRow(item, 'progressed', true)}</div>)}
            {additional.length > 0 ? <details><summary>{t('planningLineSchedule')} · {additional.length}</summary>
              {additional
                .map((slot: { order: Row }) => <div className="planning-mobile-job" key={String(slot.order.id)}>{itemRow(slot.order, 'progressed', true)}</div>)}
            </details> : !queue.current && <p className="planning-empty">{t('planningScheduleEmpty')}</p>}
          </article>;
        })}
      </div>
    </section>
    <section className="planning-section planning-requests-progressed" aria-labelledby="planning-progressed-title">
      <header><h3 id="planning-progressed-title">{t("planningProgressedTitle")} <span>{progressedGroups.length}</span></h3>
        </header>
      {progressedGroups.length ? <div className="planning-list" role="list">{progressedGroups.map((group) =>
        requestCard(group, "progressed"))}</div> :
        <p className="planning-empty">{t("planningScheduleEmpty")}</p>}
    </section>
    </div>
    {editing && !pendingReason && <div className="planning-overlay" onMouseDown={(event) => {
      if (event.target === event.currentTarget) closeEditor();
    }}><aside className="planning-drawer" ref={drawerRef} role="dialog" aria-modal="true" aria-labelledby="planning-editor-title">
      <header><div><small><bdi dir="ltr">{String(requestOf(editing)?.code || editing.code)}</bdi></small>
        <h3 id="planning-editor-title" ref={headingRef} tabIndex={-1}>{t("planProductItem")}</h3>
        <p className="planning-detail-product" style={productStyle(editing)} dir="auto">
          {localName(productOf(editing), lang)} · {amountOf(editing)}</p></div>
        <button type="button" aria-label={t("close")} onClick={closeEditor}>×</button></header>
      {editing.planning_locked_at && <p className="planning-lock-detail">{lockInfo(editing)}</p>}
      {canToggleLock(editing) && <button type="button" className="planning-lock-action"
        disabled={busy} onClick={() => void toggleLock()}>{t(editing.planning_locked_at
          ? "planningUnlockPlan" : "planningLockPlan")}</button>}
      <form onSubmit={save}>
        <label className="planning-field"><span>{t("line")}</span><select value={lineId} required
          disabled={!editableItem(editing)} onChange={(event) => chooseLine(event.target.value)}>
          <option value="">{t("chooseLine")}</option>
          {availableLines.map((line: Row) => <option key={String(line.id)} value={String(line.id)}>{localName(line, lang)}</option>)}
        </select></label>
        {!canSeeResources ? <p className="planning-warning">{t("planningResourcesPermission")}</p> :
          !availableLines.length && <p className="planning-warning">{t(dragReason(editing) || "planningNoCapableLine")}</p>}
        <label className="planning-field"><span>{t("start_time")} ({zone})</span>
          <input type="datetime-local" required value={start} disabled={!editableItem(editing)}
            onChange={(event) => setStart(event.target.value)} /></label>
        {selectedLine && <div className="planning-proposal" role="status">
          <span>{t("planningRate")}: <strong>{selectedDuration && !selectedDuration.error
            ? selectedDuration.rate + " " + unitOf(editing) + "/" + t("planningHour") : "—"}</strong></span>
          <span>{t("planningSetupDuration")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(selectedDuration.setupMinutes, lang) : "—"}</strong></span>
          <span>{t("planningProductionDuration")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(Math.ceil(selectedDuration.productionMs / 60_000), lang) : "—"}</strong></span>
          <span>{t("planningTotalWorking")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(Math.ceil(selectedDuration.totalMs / 60_000), lang) : "—"}</strong></span>
          <span>{t("planningPlannedStart")}: <strong>{proposal && !proposal.error
            ? formatTime(new Date(proposal.start).toISOString(), lang, zone) : "—"}</strong></span>
          {proposal && !proposal.error && proposal.start !== proposal.requestedStart &&
            <span className="planning-warning">{t("planningSnappedStart")}</span>}
          <span>{t("expected_finish")}: <strong>{proposal && !proposal.error
            ? formatTime(new Date(proposal.finish).toISOString(), lang, zone) : t("planningUnknownFinish")}</strong></span>
          {proposal && !proposal.error && <span className={deadlineStatus(proposal.finish, requestOf(editing)?.required_by) === "planningLate"
            ? "planning-warning" : ""}>{t(deadlineStatus(proposal.finish, requestOf(editing)?.required_by))}</span>}
        </div>}
        {suggestedGaps.length > 0 && <div className="planning-gap-choices">
          <strong>{t("planningAvailableStarts")}</strong>
          {suggestedGaps.map((gap: { start: number; finish: number; slot: { start: number } }) =>
            <button type="button" key={gap.start} disabled={!editableItem(editing)}
              onClick={() => { setStart(formatLocalInput(new Date(gap.slot.start).toISOString(), zone)); setError(""); }}>
              {formatTime(new Date(gap.slot.start).toISOString(), lang, zone)} ·
              {t("planningGapUntil")} {formatTime(new Date(gap.finish).toISOString(), lang, zone)}
            </button>)}
        </div>}
        <dl className="planning-editor-facts">
          <div><dt>{t("priority")}</dt><dd>{requestOf(editing)?.priority === "unspecified" ? t("notSpecified") : t(`priority_${requestOf(editing)?.priority || "normal"}`)}</dd></div>
          <div><dt>{t("requiredBy")}</dt><dd>{requestOf(editing)?.required_by ? formatTime(requestOf(editing)?.required_by, lang, zone) : t("notSpecified")}</dd></div>
        </dl>
        <p className="planning-field-hint">{t("planningManagerNext")}</p>
        {selectedLine && planningWarnings({ ...editing, line_id: lineId,
          start_time: start && Number.isFinite(Date.parse(start)) ? (() => { try { return localDateTimeToUtc(start, zone); } catch { return null; } })() : null }, requestOf(editing), selectedLine,
          centers, capabilities, orders).map((warning) =>
          <p className="planning-warning" key={warning}>{t(warning)}</p>)}
        {error && <p className="planning-warning" role="alert">{t(error)}</p>}
        {proposal?.error && proposal.error !== error &&
          <p className="planning-warning" role="alert">{t(proposal.error)}</p>}
        <div className="planning-actions"><button type="button" onClick={closeEditor}>{t("cancel")}</button>
          {isScheduled(editing) && <button type="button" disabled={busy || limited || !editableItem(editing)}
            onClick={() => void unschedule()}>{t("planningUnschedule")}</button>}
          <button className="primary" disabled={busy || limited || !editableItem(editing) ||
            !canSeeResources || !availableLines.length ||
            !proposal || Boolean(proposal.error)}>{t("planningSaveSchedule")}</button></div>
      </form>
      <section className="planning-history" aria-label={t("planningHistory")}>
        <h4>{t("planningHistory")}</h4>
        {historyLoading ? <p>{t("loading")}</p> : history === null
          ? <p className="planning-warning">{t("planningHistoryUnavailable")}</p>
          : history.length === 0 ? <p>{t("planningNoHistory")}</p> : <>
            <p className="planning-history-summary"><strong>{t(history[0].event === "initial"
              ? "planningInitialPlan" : "planningEarliestRecordedPlan")}:</strong>
              <span dir="ltr">{history[0].after_start
                ? historyTime(history[0].after_start) : "—"}</span>
              <bdi dir="auto">{historyLineName(history[0].after_line_id)}</bdi>
              {history[0].event === "baseline" && <span>{t("planningBaseline")}</span>}
            </p>
            <p className="planning-history-summary"><strong>{t("planningCurrentPlan")}:</strong>
              <span dir="ltr">{editing.start_time
                ? historyTime(String(editing.start_time)) : t("planningUnscheduled")}</span>
              {editing.line_id && <bdi dir="auto">{historyLineName(String(editing.line_id))}</bdi>}
            </p>
            <ol>{history.map((revision) => <li key={revision.revision_no}>
              <strong>{t("planningHistory" + revision.event[0].toUpperCase() + revision.event.slice(1))}</strong>
              <small><span dir="ltr">{historyTime(revision.changed_at)}</span>
                {revision.changed_by_name && <bdi dir="auto">{revision.changed_by_name}</bdi>}</small>
              {revision.event !== "baseline" && revision.event !== "initial" && <p className="planning-history-position">
                <span>{t("planningBefore")}: <bdi dir="auto">{historyLineName(revision.before_line_id)}</bdi></span>
                <span dir="ltr">{revision.before_start ? historyTime(revision.before_start) : "—"}
                  {" → "}{revision.before_finish ? historyTime(revision.before_finish) : "—"}</span>
              </p>}
              <p className="planning-history-position">
                <span>{t("planningAfter")}: <bdi dir="auto">{historyLineName(revision.after_line_id)}</bdi></span>
                <span dir="ltr">{revision.after_start
                  ? historyTime(revision.after_start) : t("planningUnscheduled")}
                  {revision.after_finish && " → " + historyTime(revision.after_finish)}</span>
              </p>
              {revision.reason_code && <p>{t("planningReason")}: {
                t("planningReason_" + revision.reason_code)}
                {revision.reason_note && <bdi dir="auto"> · {revision.reason_note}</bdi>}</p>}
            </li>)}</ol>
          </>}
      </section>
    </aside></div>}
    {pendingReason && <div className="planning-overlay planning-reason-overlay"
      onKeyDown={(event) => { if (event.key === "Escape" && !busy) cancelReason(); }}>
      <div className="planning-reason-dialog" role="dialog" aria-modal="true"
        aria-labelledby="planning-reason-title">
        <h3 id="planning-reason-title">{t("planningReasonTitle")}</h3>
        <p>{t("planningReasonHelp")}</p>
        <form onSubmit={submitReason}>
          <label>{t("planningReason")}<select ref={reasonSelectRef} value={reasonCode} required
            onChange={(event) => setReasonCode(event.target.value)}>
            <option value="">{t("planningChooseReason")}</option>
            {reasonCodes.map((code) => <option key={code} value={code}>{
              t("planningReason_" + code)}</option>)}
          </select></label>
          <label>{t("planningReasonNote")}<input value={reasonNote} maxLength={240}
            required={reasonCode === "other"} onChange={(event) => setReasonNote(event.target.value)} /></label>
          {error && <p role="alert" className="planning-warning">{t(error)}</p>}
          <div className="planning-actions">
            <button type="button" disabled={busy} onClick={cancelReason}>{t("cancel")}</button>
            <button type="submit" className="primary" disabled={busy || !reasonCode ||
              (reasonCode === "other" && !reasonNote.trim())}>{t("planningSaveRevision")}</button>
          </div>
        </form>
      </div>
    </div>}
  </section>;
}
