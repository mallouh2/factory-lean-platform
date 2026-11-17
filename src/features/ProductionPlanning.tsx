import MeasuredGanttCode from '@/components/MeasuredGanttCode';
import ProductionExecutionActions from './ProductionExecutionActions';
import {createPortal} from 'react-dom';
import {MaterialWarnings} from './MaterialPreparation';
import {PlanningWarningSetting,PlanningExceptionReview,planningPolicyCommand,type PlanningProtection} from './PlanningWarningPolicy';
import {startGanttDragScroll} from '@/utils/gantt-drag-scroll.mjs';
import {dragTimelineStart} from '@/utils/planning.mjs';
import {ganttLayout,ganttFocusStart} from '@/utils/planning-gantt.mjs';
import {planningTiming, sortPlanningRows, planningWorkKind} from '@/utils/planning-workspace.mjs';
import {usePlanningWork} from './usePlanningWork';
import { useEffect, useMemo, useRef, useState } from "react";
import { formatTime, localName } from "@/components/ui";
import { formatLocalInput, localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { formatDuration } from "@/utils/production-flow.mjs";
import { productionProgress } from '@/utils/production-recording.mjs';
import { orderAttention } from '@/utils/order-overview.mjs';
import ProductIdentity from '@/components/ProductIdentity';
import DeliveryContext from '@/components/DeliveryContext';
import SalesPlanningGuidance from '@/components/SalesPlanningGuidance';
import RequestOrigin from '@/components/RequestOrigin';
import { useFulfillment, type ProductionDemand } from './useFulfillment';
import { productColor } from '@/utils/product-colors.mjs';
import { MaintenancePlanningDrawer } from './MaintenancePlanning';
import MaintenanceTimelineBlock from './MaintenanceTimelineBlock';
import { useOperationalPlanningBoard } from './useOperationalPlanningBoard';
import {
  capableLines, deadlineStatus, durationMs, finishAfterWorkingMs, firstAvailable, freeGaps, lineCapacity,
  isScheduled, panViewStart, workingCalendar, workingSegments, wheelViewStart,
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

export default function ProductionPlanning({ snapshot: s, t, lang, can, command:sendCommand, refreshSnapshot, initialItemId,onOutputRelated }:
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
  const fulfillment = useFulfillment<{ rows: ProductionDemand[] }>(s, 'production', 1, can('orders'));
  const [maintenanceId,setMaintenanceId] = useState('');
  const completionRead=usePlanningWork({snapshot:s,can}),completionWork=completionRead.data;
  const [queueSort,setQueueSort]=useState('priority');
  const [workSort,setWorkSort]=useState('start');
  const [ganttWidth,setGanttWidth]=useState(1000);
  const [barTip,setBarTip]=useState<{id:string;left:number;top:number;width:number}|null>(null);
  useEffect(()=>{const clear=()=>setBarTip(null);window.addEventListener('scroll',clear,true);window.addEventListener('resize',clear);return()=>{window.removeEventListener('scroll',clear,true);window.removeEventListener('resize',clear);};},[]);
  function showBarTip(el:HTMLElement,id:string){const r=el.getBoundingClientRect(),width=Math.min(320,window.innerWidth-16);setBarTip({id,left:Math.max(8,Math.min(r.left,window.innerWidth-width-8)),top:Math.max(8,Math.min(r.bottom+8,window.innerHeight-240)),width});}
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
  const maintenanceRead = useOperationalPlanningBoard({snapshot:s,t,lang,can,command:sendCommand},rangeStart,rangeEnd,lineFilter);
  const command:FeatureProps['command']=async(name,args)=>{
    const result=await sendCommand(name,args);
    // The shared command already refreshes s.fetchedAt. Do not cancel and
    // restart the dependent board reads a second time on the same success.
    if(!refreshSnapshot){maintenanceRead.reload();completionRead.reload();}
    return result;
  };
  const headingRef = useRef<HTMLHeadingElement>(null);
  const drawerRef = useRef<HTMLElement>(null);
  const openerRef = useRef<HTMLButtonElement>(null);
  const timelineRef = useRef<HTMLDivElement>(null);
  const slotPanelRef = useRef<HTMLDivElement>(null);
  const reasonSelectRef = useRef<HTMLSelectElement>(null);
  const panStateRef = useRef<{ pointerId: number; x: number; viewStart: number; width: number } | null>(null);
  const draggingRef = useRef<string | null>(null);
  const grabOffsetRef=useRef(0),nativeDragImage=useRef<HTMLCanvasElement|null>(null);
  const lastPlacementRef=useRef<{itemId:string;lineId:string;start:number;finish:number;error?:string}|null>(null);
  const stopDragScroll=useRef<(()=>void)|null>(null);
  useEffect(()=>()=>stopDragScroll.current?.(),[]);
  function beginDrag(event:React.DragEvent<HTMLButtonElement>,order:Row,scheduled=false){
    setBarTip(null);
    stopDragScroll.current?.();stopDragScroll.current=startGanttDragScroll(event,timelineRef.current);
    grabOffsetRef.current=0;lastPlacementRef.current=null;
    if(scheduled){const lane=event.currentTarget.closest('.planning-lane-track')?.getBoundingClientRect();if(lane)grabOffsetRef.current=dragTimelineStart(rangeStart,rangeEnd,event.clientX,lane.left,lane.width)-Date.parse(String(order.start_time));}
    if(!nativeDragImage.current){nativeDragImage.current=document.createElement('canvas');nativeDragImage.current.width=1;nativeDragImage.current.height=1;}
    event.dataTransfer.setDragImage(nativeDragImage.current,0,0);
  }
  const policyReview=useRef<PlanningProtection>({fingerprint:"",required:false,confirmed:false,ready:false});
  const policyAttempt=useRef<{intent:string;id:string}|null>(null);
  const policySubmitting=useRef(false);
  const lastHoverRef = useRef<{ itemId: string; error?: string } | null>(null);
  const zone = String(s.factory?.timezone || "UTC");
  const captionClock=useMemo(()=>new Intl.DateTimeFormat(lang,{timeZone:zone,hour:'2-digit',minute:'2-digit',hourCycle:'h23'}),[lang,zone]);
  const calendar = workingCalendar(s.factory);
  // The board is range-scoped. Keep upcoming snapshot work in the list, while
  // its protected range reader wins for every item it supplies.
  const orders = [...new Map([...(s.tables.production_orders || []), ...(maintenanceRead.data?.orders || [])]
    .map(order => [String(order.id), order])).values()].map((order) =>
    optimistic && String(order.id) === optimistic.id ? { ...order, ...optimistic } : order);
  const requests = [...new Map([...(s.tables.production_requests || []), ...(maintenanceRead.data?.production_requests || [])]
    .map(request => [String(request.id), request])).values()];
  const products = s.tables.products || [];
  const lines = s.tables.production_lines || [];
  // Use the full stable ID order, so filtering/refresh cannot recolor a lane.
  const laneTones=useMemo(()=>new Map([...lines].filter(line=>!line.archived)
    .sort((a,b)=>String(a.id).localeCompare(String(b.id)))
    .map((line,index)=>[String(line.id),index%6])),[lines]);
  const centers = s.tables.work_centers || [];
  const capabilities = s.tables.work_center_capabilities || [];
  const maintenance = maintenanceRead.data?.reservations || [];
  const resourceComplete=!(s.truncatedTables||[]).some(table=>['production_lines','work_centers','work_center_capabilities','products'].includes(table)) &&
    (maintenanceRead.data?.orders||[]).every(order=>!order.line_id||lines.some(line=>!line.archived&&line.id===order.line_id)) &&
    (maintenanceRead.data?.schedules||[]).every(schedule=>(schedule.line_ids||[]).every(id=>lines.some(line=>!line.archived&&line.id===id)));
  const maintenanceReady = maintenanceRead.complete&&resourceComplete&&completionRead.complete;
  // Previous availability stays visible while revalidated; action guards still require fresh complete readers.
  const availabilityVisible=maintenanceRead.data?.completeness==='COMPLETE'&&resourceComplete;
  const sourceCovers = (line:Row,start:number,finish:number) => maintenanceReady && (!lineFilter || String(line.id)===lineFilter) &&
    Number.isFinite(start) && Number.isFinite(finish) && start>=rangeStart && finish<=rangeEnd;
  const liveOrders=orders.filter(order=>!completionWork.some(work=>work.item_id===order.id&&work.retired));
  const visualOrders = liveOrders.map(order => {const {operational_occupancy:_,...visual}=order;return visual;});
  const requestById = new Map(requests.map((request) => [String(request.id), request]));
  const active = liveOrders.filter((order) => order.status === "planned");
  const visible = (order: Row) => (!priorityFilter || requestById.get(String(order.request_id))?.priority === priorityFilter) &&
    (!productFilter || String(order.product_id) === productFilter);
  const planningItems = sortPlanningItems(active.filter((order) =>
    !isScheduled(order) && visible(order) &&
    (!lineFilter || capableLines(order, lines, centers, capabilities).some((line: Row) => String(line.id) === lineFilter))), requests);
  const progressedItems = liveOrders.filter((order) => visible(order) &&
    ["planned","active"].includes(String(order.status)) && (isScheduled(order) || order.status === "active") &&
    (!lineFilter || String(order.line_id) === lineFilter));
  const scheduled = liveOrders.filter((order) => ["planned", "active"].includes(String(order.status)) &&
    Boolean(order.line_id) && visible(order));
  const editing = orders.find((order) => String(order.id) === editingId);
  const selectedLine = lines.find((line) => String(line.id) === lineId);
  const availableLines = editing ? capableLines(editing, lines, centers, capabilities)
    .filter((line: Row) => !durationMs(editing, line, centers, capabilities).error && (!completionWork.some(w=>w.item_id===editingId)||completionWork.find(w=>w.item_id===editingId)!.capable_lines?.includes(String(line.id)))) : [];
  const editingWork=completionWork.find(w=>w.item_id===editingId),editingKind=planningWorkKind(editing,editing?requestById.get(String(editing.request_id)):undefined,editingWork);
  const editingOriginal=editingWork?.origin_code||editingWork?.demand_code||orders.find(o=>o.id===editing?.replacement_original_item_id)?.code||editing?.replacement_original_item_id;
  const priorityBadge=(order:Row)=><span className="planning-priority" data-priority={String(requestOf(order)?.priority||'normal')}>{t('priority_'+(requestOf(order)?.priority||'normal'))}</span>;
  const canEdit = can("orders", "edit");
  const editableItem = (order: Row) => canEdit && order.status === "planned" &&
    !completionWork.some(work => work.item_id === String(order.id) && work.held) &&
    (Boolean(order.execution_interrupted_at) || Number(order.produced_quantity || 0) === 0 && !order.actual_start) && !order.actual_finish && !order.planning_locked_at;
  const canToggleLock = (order: Row) => canEdit && order.status === "planned" &&
    Number(order.produced_quantity || 0) === 0 && isScheduled(order) &&
    Date.parse(String(order.start_time)) > Date.now();
  // A new assignment is routine even when historical revisions exist.
  const needsPlanningReason = (order: Row) => isScheduled(order);
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
    editableItem(order) ? completionWork.some(w=>w.item_id===String(order.id)&&!w.capable_lines.includes(String(line.id)))?{error:'planningIncompatibleLine'}:durationMs(order, line, centers, capabilities) :
    { error: order?.planning_locked_at ? "planningLockedMessage" : "planningAlreadyStarted" };
  function planningMessage(key:string,order?:Row,line?:Row,placement?:{start:number;finish:number}){
    if((key==='planningOverlap'||key==='planningNoFit')&&order&&line&&placement){
      const conflict=sortedLineSchedule(line,orders,centers,capabilities,String(order.id),calendar,zone,maintenance,String(order.product_id)).find((slot:any)=>slot.finish!==null&&placement.start<slot.finish&&placement.finish>slot.start);
      if(conflict){const interval=(Number.isFinite(conflict.start)?formatTime(new Date(conflict.start).toISOString(),lang,zone):'—')+' — '+(Number.isFinite(conflict.finish)?formatTime(new Date(conflict.finish).toISOString(),lang,zone):t('planningUnknownFinish'));
        return (conflict.maintenance?t('planningMaintenanceConflict'):t('planningOrderConflict')+' '+String(conflict.order.code||conflict.order.id))+' · '+interval;}
    }
    if(key!=='planningIncompatibleLine'||!order||!line)return key;
    const w=completionWork.find(w=>w.item_id===String(order.id)),required=(w?.required_operations||[]).map(op=>lang==='ar'?op.name_ar||op.name:op.name).filter(Boolean);
    const onLine=centers.filter(center=>center.line_id===line.id&&!center.archived),categories=s.tables.work_center_categories||[];
    const processes=[...new Set(onLine.map(center=>categories.find(cat=>cat.id===center.category_id)).filter(Boolean).map(cat=>localName(cat!,lang)))].filter(Boolean);
    const requiredText=required.length?required.join(' + '):localName(productOf(order),lang),supported=processes.join(' + ');
    return lang==='ar'?'لا يمكن جدولة '+String(order.code)+' على '+localName(line,lang)+'. المطلوب: '+requiredText+(supported?'؛ عمليات الخط: '+supported:'')+'. اختر خطاً متوافقاً.':'Cannot schedule '+String(order.code)+' on '+localName(line,lang)+'. Required: '+requiredText+(supported?'; line processes: '+supported:'')+'. Choose a compatible line.';
  }
  const resourceLimited = !resourceComplete;
  const limited = !maintenanceReady || resourceLimited;
  function dragReason(order: Row) {
    if (completionWork.some(work => work.item_id === String(order.id) && work.held)) return 'planningQualityHold';
    if (order.planning_locked_at) return "planningLockedMessage";
    if (order.status !== "planned") return planningBoardStatus(order);
    if ((!order.execution_interrupted_at && (Number(order.produced_quantity || 0) > 0 || order.actual_start)) || order.actual_finish) return "planningAlreadyStarted";
    const candidates = capableLines(order, lines, centers, capabilities);
    const checks = candidates.map((line: Row) => durationMs(order, line, centers, capabilities));
    if (checks[0]?.error === "planningMissingRate" && !["meter", "piece", "kg"].includes(String(order.unit)))
      return "planningLegacyUnit";
    return checks.some((check: { error?: string }) => !check.error) ? "" :
      checks[0]?.error || "planningIncompatibleLine";
  }
  const canDragItem = (order: Row) => editableItem(order) && maintenanceReady && !limited && canSeeResources &&
    !busy && !savingDropId && !dragReason(order);
  const maintenanceSchedules = maintenanceRead.data?.schedules || [];
  const maintenanceForLine = (line: Row) => maintenanceSchedules.filter(schedule => (schedule.line_ids || []).includes(String(line.id)));
  const independentSchedules = maintenanceSchedules.filter(schedule => !schedule.line_ids?.length);
  const openMaintenance = (id:string) => {setMaintenanceId(id);setEditingId(null);};
  const maintenanceRequest = maintenanceRead.data?.requests.find(request => request.id===maintenanceId);
  const visibleLines = lines.filter((line) => !line.archived && (!lineFilter || String(line.id) === lineFilter));
  const lineSchedules = new Map(visibleLines.map((line) => [String(line.id),
    sortedLineSchedule(line, visualOrders, centers, capabilities, null, calendar, zone)]));
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
      : zoomIndex === 1 ? { hour: "2-digit" as const, ...(rangeStart%3600000?{minute:"2-digit" as const}:{}), hourCycle: "h23" as const }
      : zoomIndex === 2 ? { month: "short" as const, day: "numeric" as const,
          hour: "numeric" as const, hourCycle: "h23" as const }
      : { month: "short" as const, day: "numeric" as const }),
  }).format(time);
  const localStartDay=formatLocalInput(new Date(rangeStart).toISOString(),zone).slice(0,10);
  const dayBoundaries=useMemo(()=>Array.from({length:Math.ceil(scale.span/86400000)+2},(_,n)=>{
    const day=new Date(Date.parse(localStartDay+'T00:00:00Z')+n*86400000).toISOString().slice(0,10);
    return Date.parse(localDateTimeToUtc(day+'T00:00',zone));
  }).filter(time=>time>rangeStart&&time<rangeEnd),[localStartDay,scale.span,rangeStart,rangeEnd,zone]);
  const jobsInView=visibleLines.reduce((count,line)=>count+ganttLayout(lineSchedules.get(String(line.id))||[],rangeStart,rangeEnd,ganttWidth).jobs.length,0);
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
    editingId, calendar, zone, maintenance,editing?.product_id) : [];
  const selectedDuration: any = editing && selectedLine ? durationMs(editing, selectedLine, centers, capabilities) : null;
  const proposedStart = (() => { try { return start ? Date.parse(localDateTimeToUtc(start, zone)) : NaN; }
    catch { return NaN; } })();
  const manualScopeKnown=Boolean(Number.isFinite(proposedStart)&&selectedLine&&selectedDuration&&!selectedDuration.error&&availabilityVisible&&(!lineFilter||String(selectedLine.id)===lineFilter)&&proposedStart>=rangeStart&&finishAfterWorkingMs(proposedStart,selectedDuration.totalMs,calendar,zone)<=rangeEnd);
  const proposal: any = editing && selectedLine && Number.isFinite(proposedStart)
    ? proposeSchedule(editing, selectedLine, proposedStart, manualScopeKnown?orders:[], centers, capabilities,
      Date.now(), calendar, zone, manualScopeKnown?maintenance:[]) : null;
  if(proposal&&!manualScopeKnown)proposal.server_validation_required=true;
  const suggestedGaps: any[] = availabilityVisible && selectedDuration && !selectedDuration.error ?
    freeGaps(selectedSchedule, Math.max(Date.now(), rangeStart), rangeEnd).gaps
      ?.map((gap: { start: number; finish: number }) => ({ ...gap,
        slot: firstAvailable([], gap.start, selectedDuration.totalMs, gap.finish, calendar, zone) }))
      .filter((gap: { slot: { error?: string;start?:number;finish?:number } }) => !gap.slot.error&&Number.isFinite(gap.slot.start)&&Number.isFinite(gap.slot.finish)).slice(0, 6) || [] : [];

  useEffect(() => {
    if (editing) headingRef.current?.focus();
  }, [editingId, Boolean(editing)]);
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
        "button:not([disabled]), select:not([disabled]), input:not([disabled]), summary, a[href]");
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
  }, [editingId, Boolean(editing)]);
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
  const unitOf = (order: Row) => t(order.unit === "meter" ? "meterShort" : order.unit === "piece" ? "pieceShort" : order.unit === "kg" ? "kg" : "legacyUnit");
  const amountOf = (order: Row) => `${Number(order.target_quantity).toLocaleString(lang)} ${unitOf(order)}`;
  const requestOf = (order: Row) => requestById.get(String(order.request_id));

  function openEditor(order: Row, proposedLine = String(order.line_id || ""), proposedTime?: number) {
    openerRef.current = document.activeElement instanceof HTMLButtonElement ? document.activeElement : null;
    setEditingId(String(order.id));
    setLineId(proposedLine);
    const line = lines.find((candidate) => String(candidate.id) === proposedLine);
    const duration: any = line ? durationMs(order, line, centers, capabilities) : null;
    const next: any = maintenanceReady && line && (!lineFilter || String(line.id)===lineFilter) && duration && !duration.error
      ? firstAvailable(sortedLineSchedule(line, orders, centers, capabilities, String(order.id), calendar, zone, maintenance,order.product_id),
        Math.max(rangeStart,Math.ceil(Date.now() / 900_000) * 900_000), duration.totalMs,
        rangeEnd, calendar, zone) : null;
    const initial = proposedTime ?? (order.start_time ? Date.parse(String(order.start_time)) : next?.start);
    setStart(Number.isFinite(initial) ? formatLocalInput(new Date(initial).toISOString(), zone, true) : "");
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
    if (!pendingReason || policySubmitting.current) return;
    if (!reasonCodes.includes(reasonCode as typeof reasonCodes[number]) ||
      (reasonCode === "other" && !reasonNote.trim())) {
      setError("planningReasonRequired"); return;
    }
    if(!policyReview.current.ready||policyReview.current.required&&(!policyReview.current.confirmed||!reasonNote.trim())){setError('planning_confirmation_required');return;}
    const pending = pendingReason;
    policySubmitting.current=true;setBusy(true); setError("");
    try {
      const args={factory:s.factory?.id,item:pending.item,target_line:pending.target_line,planned_start:pending.planned_start,reason_code:reasonCode,reason_note:reasonNote.trim(),expected_fingerprint:policyReview.current.fingerprint,exception_confirmed:policyReview.current.confirmed};
      const intent=JSON.stringify(args);if(policyAttempt.current?.intent!==intent)policyAttempt.current={intent,id:crypto.randomUUID()};
      await planningPolicyCommand('revise_product_plan_confirmed',{...args,request_id:policyAttempt.current!.id});policyAttempt.current=null;
      // This endpoint bypasses the shared command handler. Reload confirmed
      // schedule data now instead of waiting for the background snapshot poll.
      if(refreshSnapshot)await refreshSnapshot();
      else {maintenanceRead.reload();completionRead.reload();}
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
      policySubmitting.current=false;setBusy(false);
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
    if(!availableLines.some((candidate:Row)=>String(candidate.id)===nextLineId)){setStart("");setError("planningIncompatibleLine");return;}
    const duration: any = durationMs(editing, line, centers, capabilities);
    if (duration.error) { setStart(""); setError(duration.error); return; }
    const slot: any = firstAvailable(sortedLineSchedule(line, orders, centers, capabilities,
      String(editing.id), calendar, zone, maintenance,editing.product_id),
      Math.max(rangeStart,Math.ceil(Date.now() / 900_000) * 900_000), duration.totalMs,
      rangeEnd, calendar, zone);
    setStart(Number.isFinite(slot.start) ? formatLocalInput(new Date(slot.start).toISOString(), zone, true) : "");
    setError(slot.error || "");
  }
  function previewAt(event: React.DragEvent<HTMLDivElement>, line: Row, order: Row) {
    const eligibility:any=dropValidity(order,line);
    if(eligibility.error)return {error:eligibility.error,start:NaN,finish:NaN};
    const rect = event.currentTarget.getBoundingClientRect();
    const raw=dragTimelineStart(rangeStart,rangeEnd,event.clientX,rect.left,rect.width,grabOffsetRef.current);
    return previewPlacement(order, line, raw, orders, centers, capabilities, {
      from: rangeStart, until: rangeEnd, increment: snapIncrement, calendar, zone, maintenance,
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
    if (validity.error) { setError(planningMessage(validity.error,order,line)); setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450); return; }
    const last=lastPlacementRef.current;
    const placement:any=last?.itemId===id&&last.lineId===String(line.id)
      ?last.error?last:proposeSchedule(order,line,last.start,orders,centers,capabilities,Date.now(),calendar,zone,maintenance)
      :previewAt(event,line,order);
    if(last?.itemId===id&&last.lineId===String(line.id)&&!last.error&&placement.finish!==last.finish)placement.error='planningAvailabilityChanged';
    grabOffsetRef.current=0;lastPlacementRef.current=null;
    if (!sourceCovers(line,placement.start,placement.finish))placement.error='mpBoardOutside';
    if (placement.error) { setError(planningMessage(placement.error,order,line,placement)); setRejectedId(id);
      setTimeout(() => setRejectedId(null), 450); return; }
    const startTime = new Date(placement.start).toISOString();
    if (isScheduled(order) && String(order.line_id) === String(line.id) &&
      Date.parse(String(order.start_time)) === placement.start) return;
    setError(""); setSavingDropId(id); setSettlingId(id);
    setOptimistic({ id, line_id: String(line.id), start_time: startTime,
      expected_finish: new Date(placement.finish).toISOString() });
    if (needsPlanningReason(order)) {
      askReason({ source: "drop", item: id, target_line: String(line.id),
        planned_start: startTime });
      return;
    }
    try {
      await command("plan_product_item", { factory: s.factory?.id, item: order.id,
        target_line: line.id, planned_start: startTime });
    } catch (cause) {
      setError(planningMessage(cause instanceof Error && cause.message ? cause.message : "planningSaveFailed",order,line));
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
    stopDragScroll.current?.();stopDragScroll.current=null;
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
    if (!completionRead.complete) {setError('mpAvailabilityUnknown');return;}
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
    const duration:any=durationMs(editing,selectedLine,centers,capabilities);
    const scoped=!duration.error&&sourceCovers(selectedLine,Date.parse(utc),finishAfterWorkingMs(Date.parse(utc),duration.totalMs,calendar,zone));
    // Manual placement retains protected server validation; no missing occupancy is treated as free.
    const check: any = proposeSchedule(editing, selectedLine, Date.parse(utc), scoped?orders:[], centers, capabilities,
      Date.now(), calendar, zone, scoped?maintenance:[]);
    if (check.error) { setError(check.error); return; }
    if (needsPlanningReason(editing) && (
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
    if (!completionRead.complete) {setError('mpAvailabilityUnknown');return;}
    if (!editing) return;
    if (!editableItem(editing)) {
      setError(editing.planning_locked_at ? "planningLockedMessage" : "planningAlreadyStarted");
      return;
    }
    askReason({ source: "unschedule", item: String(editing.id), target_line: null, planned_start: null });
  }

  async function findSlots(order: Row) {
    if (!maintenanceReady || limited) {setError('mpAvailabilityUnknown');return;}
    const now = Date.now();
    const searchStart=Math.max(rangeStart,Math.ceil(now/900_000)*900_000);
    const result = suggestPlanningSlots(order, requestOf(order), lines.filter(line=>!lineFilter||String(line.id)===lineFilter), orders, centers, capabilities,
      { now:searchStart, horizonDays:Math.max(0,(rangeEnd-searchStart)/86400000), limit: 3, calendar, zone, maintenance });
    const linked = fulfillment.data?.rows.some(row => row.item_id === String(order.id) && row.target_ready)
      || ['SALES_PRODUCTION','STOCK_REPLENISHMENT'].includes(String(requestOf(order)?.request_type));
    if (linked) {
      setBusy(true);
      try {
        const response = await fetch('/api/fulfillment?' + new URLSearchParams({ factory: String(s.factory?.id), mode: 'guidance', item: String(order.id) }), { cache: 'no-store' });
        const guidance = await response.json();
        if (!response.ok) throw Error(guidance.error || 'dataWarning');
        const candidate = guidance.suggestion;
        const line = candidate && lines.find(row => String(row.id) === candidate.line);
        if (line) {
          const check: any = proposeSchedule(order, line, Date.parse(candidate.start), orders, centers, capabilities, now, calendar, zone, maintenance);
          const target = Date.parse(guidance.state === 'tight' ? guidance.requested_delivery : guidance.target_ready);
          if (!check.error && sourceCovers(line,check.start,check.finish) && check.finish <= target) {
            const schedule = sortedLineSchedule(line, orders, centers, capabilities, String(order.id), calendar, zone, maintenance,order.product_id);
            result.suggestions = [{ lineId: String(line.id), start: check.start, finish: check.finish, setupMs: check.setupMs,
              productionMs: check.productionMs, totalMs: check.durationMs, rate: check.rate,
              deadline: deadlineStatus(check.finish, new Date(target).toISOString(), now),
              load: lineCapacity(schedule, rangeStart, rangeEnd, calendar, zone) },...result.suggestions.filter(slot=>slot.lineId!==String(line.id)||slot.start!==check.start)];
            result.reason = 'salesBackwardAdvisory';
          } else result.reason = 'salesTargetNoSlot';
        } else if (guidance.requested_delivery) result.reason = 'salesTargetNoSlot';
      } catch (cause) { setError(cause instanceof Error ? cause.message : 'dataWarning'); setBusy(false); return; }
      finally { setBusy(false); }
    }
    setSlotSearch({ itemId: String(order.id), ...result });
    setSlotChoice(null);
    setError("");
  }

  async function confirmSlot() {
    if (!maintenanceReady || !slotOrder || !chosenSlot || busy || limited || !canSeeResources || !editableItem(slotOrder)) return;
    const line = lines.find((candidate) => String(candidate.id) === chosenSlot.lineId);
    if (!line || !capableLines(slotOrder, lines, centers, capabilities).some((candidate: Row) =>
      String(candidate.id) === chosenSlot.lineId)) { setError("planningInvalidSelection"); return; }
    const check: any = proposeSchedule(slotOrder, line, chosenSlot.start, orders, centers, capabilities,
      Date.now(), calendar, zone, maintenance);
    if(!sourceCovers(line,check.start,check.finish))check.error='mpBoardOutside';
    if (check.error || check.finish !== chosenSlot.finish || check.start !== chosenSlot.start) {
      setError(check.error || "planningSlotChanged"); return;
    }
    const plannedStart = new Date(chosenSlot.start).toISOString();
    if (needsPlanningReason(slotOrder)) {
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
        beginDrag(event,order,event.currentTarget.classList.contains("planning-gantt-block"));event.dataTransfer.setData("text/plain", String(order.id));
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
      {requestOf(order)?.request_type === 'INTERNAL_PRODUCTION' && <RequestOrigin request={requestOf(order)} t={t} lang={lang} zone={zone} />}
      {Boolean(order.line_id && order.start_time) && <span className="planning-product-schedule">
        <bdi dir="auto">{localName(lines.find(line => line.id === order.line_id), lang)}</bdi>
        <span>{t('executionPlannedStart')}: {formatTime(order.start_time, lang, zone)}</span>
        {order.expected_finish && <span>{t('executionPlannedFinish')}: {formatTime(order.expected_finish, lang, zone)}</span>}
      </span>}
      {order.status === 'active' && <span className="planning-product-schedule">{t('recordingGoodSoFar')}: {productionProgress(order).good.toLocaleString(lang)} {unitOf(order)}</span>}
      {requestOf(order)?.request_type !== 'INTERNAL_PRODUCTION' && <DeliveryContext rows={fulfillment.data?.rows || []} item={order.id} t={t} lang={lang} zone={zone} />}
      {blockedReason && <small className="planning-drag-reason">{t(blockedReason)}</small>}
    </button>{section === "waiting" && canDrag &&
      <button type="button" className="planning-find-slot" disabled={busy || Boolean(savingDropId)}
        onClick={() => findSlots(order)}>{t("planningFindSlot")}</button>}</div>;
  }

  function compactTable(items: Row[], waiting: boolean) {
    return <div className="planning-table-scroll" tabIndex={0} role="region" aria-label={t(waiting?'planningWaitingTitle':'planningProgressedTitle')}>
      <table className="planning-work-table"><thead><tr>
        <th scope="col">{t('planningOrderReference')}</th><th scope="col">{t('product')}</th><th scope="col">{t('quantity')}</th><th scope="col">{t('planningWorkType')}</th>
        {waiting ? <><th scope="col">{t('priority')}</th><th scope="col">{t('requiredBy')}</th><th scope="col">{t('planningEligibility')}</th></> :
          <><th scope="col">{t('priority')}</th><th scope="col">{t('line')}</th><th scope="col">{t('executionPlannedStart')}</th><th scope="col">{t('executionPlannedFinish')}</th><th scope="col">{t('status')}</th></>}
      </tr></thead><tbody>{items.map(order=>{
        const blocked=dragReason(order), timing=planningTiming(order,requestOf(order));
        const recovery=completionWork.find(w=>w.item_id===String(order.id));
        return <tr key={String(order.id)} data-item-id={String(order.id)} data-request-id={String(order.request_id)}
          data-selected={editingId===String(order.id)} data-state={visualState(order)}>
          <td data-label={t('planningOrderReference')}><button type="button" className="planning-product-card planning-table-select" title={lockInfo(order)||(blocked?t(blocked):undefined)} draggable={canDragItem(order)}
            disabled={!can('orders','view')||Boolean(savingDropId)} onClick={()=>openEditor(order)}
            aria-label={t('planningOpenDetails')+' '+String(order.code)+' · '+localName(productOf(order),lang)+' · '+amountOf(order)+' · '+t(planningBoardStatus(order))}
            onDragStart={event=>{if(!canDragItem(order)){event.preventDefault();return;}
              beginDrag(event,order);event.dataTransfer.setData('text/plain',String(order.id));event.dataTransfer.effectAllowed='move';
              draggingRef.current=String(order.id);lastHoverRef.current=null;setDraggingId(String(order.id));setError('');}}
            onDragEnd={()=>finishDrag(String(order.id))}><bdi dir="ltr">{String(order.code||requestOf(order)?.code)}</bdi></button></td>
          <td data-label={t('product')}><DeliveryContext rows={fulfillment.data?.rows||[]} item={order.id} t={t} lang={lang} zone={zone}/><ProductIdentity productId={order.product_id} productItemId={order.id}>{localName(productOf(order),lang)}</ProductIdentity></td>
          <td data-label={t('quantity')}>{amountOf(order)}</td><td data-label={t('planningWorkType')}>{t(planningWorkKind(order,requestOf(order),recovery).type)}</td>
          {waiting?<><td data-label={t('priority')}>{requestOf(order)?.priority==='unspecified'?t('notSpecified'):priorityBadge(order)}</td><td data-label={t('requiredBy')}>{requestOf(order)?.required_by?formatTime(requestOf(order)?.required_by,lang,zone):'—'}</td>
            <td data-label={t('planningEligibility')}>{recovery?.held?<strong className="planning-warning">{t('planningQualityHold')}</strong>:blocked?<span className="planning-warning">{t(blocked)}</span>:t('planningReadyToSchedule')}
              {timing&&<small className="planning-warning">{t(timing)}</small>}</td></>:<>
            <td data-label={t('priority')}>{priorityBadge(order)}</td><td data-label={t('line')}>{historyLineName(String(order.line_id||''))}</td><td data-label={t('executionPlannedStart')}>{order.start_time?formatTime(order.start_time,lang,zone):'—'}</td>
            <td data-label={t('executionPlannedFinish')}>{order.expected_finish?formatTime(order.expected_finish,lang,zone):'—'}</td>
            <td data-label={t('status')}><span className="planning-status" data-state={order.status}>{t(planningBoardStatus(order))}</span>
              {order.planning_locked_at&&<small>{t('planningLocked')}</small>}{recovery?.held&&<small className="planning-warning">{t('planningQualityHold')}</small>}
              {timing&&<small className="planning-warning">{t(timing)}</small>}</td></>}
        </tr>;
      })}</tbody></table>
    </div>;
  }

  function showSchedule(item?:Row) {
    const next=ganttFocusStart(item?[item]:scheduled.filter(o=>!lineFilter||String(o.line_id)===lineFilter),Date.now(),scale.span);
    if(next===null)return;setViewStart(next);if(item)closeEditor();
    requestAnimationFrame(()=>{const chart=timelineRef.current;if(chart){chart.scrollLeft=0;chart.scrollIntoView({block:'center'});chart.focus({preventScroll:true});if(item)chart.querySelector(`[data-item-id="${String(item.id)}"] .planning-job-caption`)?.scrollIntoView({block:'nearest',inline:'nearest'});}});
  }
  useEffect(()=>{
    const element=timelineRef.current?.querySelector('.planning-axis-track');if(!element)return;
    const measure=()=>{const width=element.getBoundingClientRect().width;if(width>0)setGanttWidth(old=>Math.abs(old-width)>1?width:old);};
    measure();const observer=new ResizeObserver(measure);observer.observe(element);return()=>observer.disconnect();
  },[]);
  function changeZoom(next: number) {
    const bounded = Math.max(0, Math.min(zoomLevels.length - 1, next));
    setViewStart((current) => zoomViewStart(current, scale.span, zoomLevels[bounded].span));
    setZoomIndex(bounded);
  }

  const tipOrder=barTip?orders.find(o=>String(o.id)===barTip.id):null;
  return <section className="planning-page planning-v3 ops-workbench" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
    {barTip&&tipOrder&&!draggingId&&typeof document!=='undefined'&&createPortal(<div id="planning-bar-tooltip" role="tooltip" className="planning-bar-tooltip" dir={lang==='ar'?'rtl':'ltr'} style={{left:barTip.left,top:barTip.top,width:barTip.width,maxHeight:`calc(100dvh - ${barTip.top}px - 8px)`}}><strong><bdi>{String(tipOrder.code)}</bdi></strong><DeliveryContext rows={fulfillment.data?.rows||[]} item={tipOrder.id} t={t} lang={lang} zone={zone}/><p>{localName(productOf(tipOrder),lang)} · {amountOf(tipOrder)}</p><p>{localName(lines.find(l=>l.id===tipOrder.line_id),lang)}</p><dl>{[[t('executionPlannedStart'),formatTime(tipOrder.start_time,lang,zone)],[t('executionPlannedFinish'),formatTime(tipOrder.expected_finish,lang,zone)],[t('planningTotalWorking'),Number.isFinite(Date.parse(String(tipOrder.expected_finish)))?formatDuration(Math.ceil((Date.parse(String(tipOrder.expected_finish))-Date.parse(String(tipOrder.start_time)))/60000),lang):t('planningUnknownFinish')],[t('status'),t(planningBoardStatus(tipOrder))]].map(([label,value])=><div key={label}><dt>{label}</dt><dd>{value}</dd></div>)}</dl></div>,document.body)}
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
    {!canSeeResources && <p className="planning-warning-banner" role="status">{t('planningResourcesPermission')}</p>}
    <div className="planning-read-state" role="status" aria-live="off" data-board-completeness={maintenanceReady?'COMPLETE':maintenanceRead.error?'ERROR':'INCOMPLETE'} data-warning={!maintenanceReady&&!maintenanceRead.loading&&!completionRead.loading}>
     <span role={maintenanceRead.error||completionRead.error?'alert':undefined}>{t(maintenanceReady?'planningAvailabilityReady':(maintenanceRead.loading||completionRead.loading)&&(maintenanceRead.data?.completeness==='COMPLETE'||completionWork.length>0)?'planningAvailabilityUpdating':maintenanceRead.error||completionRead.error?'mpBoardError':'mpAvailabilityUnknown')}</span>
     <button type="button" disabled={maintenanceRead.loading||completionRead.loading} style={{visibility:maintenanceReady||maintenanceRead.loading||completionRead.loading?'hidden':'visible'}} onClick={()=>{maintenanceRead.reload();completionRead.reload();}}>{t('refresh')}</button>
    </div>
    {error && !editing && <p className="planning-warning-banner" role="alert">{t(error)}</p>}
    <div className="planning-workspace">
    <section className="planning-section planning-requests-waiting" aria-labelledby="planning-needs-title">
      <header><h3 id="planning-needs-title">{t("planningWaitingTitle")} <span>{planningItems.length}</span></h3>
        </header>
      <div className="planning-queue-help"><p>{t('planningQueueHelp')}</p><label>{t('planningSort')} <select value={queueSort} onChange={e=>setQueueSort(e.target.value)}>
        <option value="priority">{t('priority')}</option><option value="required">{t('requiredBy')}</option><option value="reference">{t('planningOrderReference')}</option></select></label></div>
      {planningItems.length ? compactTable(sortPlanningRows(planningItems,requests,queueSort),true) :
        <p className="planning-empty">{t("planningQueueEmpty")}</p>}
    </section>
    <section className="planning-section planning-gantt" aria-labelledby="planning-scheduled-title">
      <header><h3 id="planning-scheduled-title">{t("planningTimelineTitle")} <span>{scheduled.length}</span></h3>
        </header>
    <details className="planning-support"><summary>{t("planningScheduleDetails")}</summary>
    <section className="planning-summary" aria-label={t("planningSummary")}>
      <dl>
        <div><dt>{t("planningSummaryWaiting")}</dt><dd>{formatQuantity(summary.waiting)}</dd></div>
        <div><dt>{t("planningSummaryPlanned")}</dt><dd>{formatQuantity(summary.planned)}</dd></div>
        <div><dt>{t("planningSummaryAtRisk")}</dt><dd>{formatQuantity(summary.atRisk)}</dd></div>
        <div><dt>{t("planningSummaryLate")}</dt><dd>{formatQuantity(summary.late)}</dd></div>
      </dl>
      <small title={t('planningSummaryScope')}>{t('planningVisibleScope')}</small>
    </section>
      <p data-board-completeness={maintenanceReady?'COMPLETE':'INCOMPLETE'}>{t(maintenanceReady?'mpBoardComplete':'mpAvailabilityUnknown')} · {maintenanceRead.data?.loaded||0} / {maintenanceRead.data?.total??'—'}</p>
      <p>{maintenanceRead.data?.active!==true&&t('mpActivationBlocked')} {t('mpGapAdvisory')}</p>
      <p className="mp-timeline-legend">⚙ {t('mpReservationLegend')} · ━ {t('mpPhysicalStops')}</p>
    </details>
      {slotSearch && slotOrder && <div className="planning-slot-panel" ref={slotPanelRef} role="region"
        aria-label={t("planningSlotSuggestions")}>
        <div className="planning-slot-heading"><div><strong>{t("planningSlotSuggestions")}</strong>
          <span dir="auto">{localName(productOf(slotOrder), lang)} · {amountOf(slotOrder)}</span></div>
          <button type="button" aria-label={t("close")} onClick={() => {
            setSlotSearch(null); setSlotChoice(null); setError(""); }}>×</button></div>
        {slotSearch.reason && slotSearch.suggestions.length > 0 && <p className="planning-warning" role="status">{t(slotSearch.reason)}</p>}
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
      <div className="planning-date-navigation" aria-label={t('planningTimelineTitle')}>
        <button type="button" onClick={()=>setViewStart(v=>v-scale.span)}>{t('planningPrevious')}</button>
        <button type="button" onClick={()=>setViewStart(Date.parse(localDateTimeToUtc(formatLocalInput(new Date().toISOString(),zone).slice(0,10)+'T00:00',zone)))}>{t('planningToday')}</button>
        <button type="button" onClick={()=>setViewStart(v=>v+scale.span)}>{t('planningNext')}</button>
        <span className="planning-visible-range">{formatTime(new Date(rangeStart).toISOString(),lang,zone)} — {formatTime(new Date(rangeEnd).toISOString(),lang,zone)}</span>
        <button type="button" disabled={!scheduled.some(o=>o.start_time&&(!lineFilter||o.line_id===lineFilter))} onClick={()=>showSchedule()}>{t('planningFindScheduled')}</button>
        <button type="button" aria-pressed={zoomIndex===1} onClick={()=>changeZoom(1)}>{t('planningDay')}</button>
        <button type="button" aria-pressed={zoomIndex===3} onClick={()=>changeZoom(3)}>{t('planningWeek')}</button>
      </div>
      <p className="planning-range-summary">{jobsInView} {t('planningJobsInView')}</p>
      <MaterialWarnings props={{snapshot:s,t,lang,can,command}}/><details className="planning-support"><summary>{t('planningAdvancedRange')}</summary><div className="planning-board-toolbar"><PlanningWarningSetting props={{snapshot:s,t,lang,can,command}}/>
        <label className="planning-window-start"><span>{t("planningVisibleStart")}</span>
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
      </details>
      <div className="planning-gantt-v4"><div ref={timelineRef}
        className={"planning-timeline-scroll" + (panning ? " planning-panning" : "")}
        dir="ltr" tabIndex={0} role="region" aria-label={t('planningTimelineTitle')}
        onPointerDown={beginPan} onPointerMove={movePan}
        onPointerUp={endPan} onPointerCancel={endPan}>
        <div className="planning-timeline" dir="ltr" style={{ minWidth: scale.minWidth }}>
          <div className="planning-axis"><span className="planning-line-label">{t("line")}</span>
            <div className="planning-axis-track">{ticks.map((tick, index) =>
              <span key={tick} data-tick={index===ticks.length-1?'':tickLabel(tick)} data-day-start={formatLocalInput(new Date(tick).toISOString(),zone).slice(11,16)==='00:00'} style={{ left: position(tick) + "%" }}>{index === ticks.length - 1 ? "" : tickLabel(tick)}</span>)}{zoomIndex<=1&&[rangeStart,...dayBoundaries].map(day=><span className="planning-axis-date" key={'day-'+day} style={{left:position(day)+'%'}}>{new Intl.DateTimeFormat(lang,{timeZone:zone,month:'short',day:'numeric'}).format(day)}</span>)}</div>
          </div>
          {visibleLines.map((line) => {
            const schedule = lineSchedules.get(String(line.id)) || [];
            const gaps = availabilityVisible ? freeGaps(sortedLineSchedule(line, orders, centers, capabilities,
              draggingId, calendar, zone, maintenance,dragging?.product_id),rangeStart,rangeEnd).gaps || [] : [];
            const maintenanceBlocks = maintenanceForLine(line);
            const conflicts = overlappingItems(sortedLineSchedule(line,visualOrders,centers,capabilities,null,calendar,zone,maintenance));
            const layout=ganttLayout(schedule,rangeStart,rangeEnd,ganttWidth,maintenanceBlocks),stacked=layout.jobs;
            const dropState: any = dragging ? dropValidity(dragging, line) : null;
            const linePreview = hoverPreview?.lineId === String(line.id) ? hoverPreview : null;
            const dropClass = dragging ? dropState?.error || linePreview?.error ?
              " planning-drop-invalid" : " planning-drop-valid" : "";
            return <div className={"planning-lane" + dropClass +
              (linePreview ? " planning-drop-hover" : "")} key={String(line.id)} data-line-id={String(line.id)} data-lane-tone={laneTones.get(String(line.id))}>
              <strong className="planning-line-label" dir={lang === 'ar' ? 'rtl' : 'ltr'}>
                <span className="planning-line-name">{localName(line, lang)}</span>
                {line.paused_at && <small className="planning-lane-paused">{t('planningLinePaused')}</small>}
                <small className="planning-lane-count">{stacked.length} {t(stacked.length===1?'planningScheduledJob':'planningScheduledJobs')}</small>
                {dragging && <small className={dropState?.error || linePreview?.error ? "planning-warning" : "planning-drop-hint"}>
                  {dropState?.error || linePreview?.error ? t(planningMessage(dropState?.error || linePreview?.error || "",dragging,line,linePreview||undefined)) :
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
                   lastPlacementRef.current=next;
                   lastHoverRef.current = { itemId: next.itemId, error: next.error ? planningMessage(next.error,draggedOrder,line,next) : undefined };
                  setHoverPreview((previous) => previous?.itemId === next.itemId &&
                    previous.lineId === next.lineId && previous.start === next.start &&
                    previous.error === next.error ? previous : next);
                }}
                onDragLeave={(event) => { if (!event.currentTarget.contains(event.relatedTarget as Node)) setHoverPreview(null); }}
                onDrop={(event) => { if (canEdit && !limited && canSeeResources && !savingDropId) void dropItem(event, line); }}
                style={{ height: Math.max(68, 12 + (layout.tracks + layout.unknown.length) * 60) }}>
                {dayBoundaries.map(day=><i className="planning-day-boundary" key={'day-'+day} style={{left:position(day)+'%'}}/>)}
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
                {stacked.map((slot: any) => {
                  const order = slot.order as Row;
                  const finish = slot.finish ?? slot.start;
                  const blockWidth=slot.width;
                  const request = requestOf(order);
                  const dueState = riskOf(slot);
                  const hasRisk = dueState === "planningLate" || dueState === "planningAtRisk";
                  const warning=conflicts.has(String(order.id))?'planningOverlap':visualState(order)==='delayed'?'delayed':hasRisk?dueState:null;
                  return <button type="button" key={String(order.id)}
                    data-state={conflicts.has(String(order.id)) ? 'blocked' : visualState(order)}
                    className={"planning-gantt-block" + (dueState === "planningLate" ? " planning-gantt-late" :
                      dueState === "planningAtRisk" ? " planning-gantt-risk" : "") +
                      (hasRisk ? " planning-has-risk" : "") +
                      (order.status === 'active' ? ' planning-gantt-active' : '') +
                      (order.planning_locked_at ? ' planning-gantt-locked' : '') +
                      (conflicts.has(String(order.id)) ? " planning-gantt-conflict" : "") +
                      (slot.compact ? " planning-gantt-compact" : "") +
                      (settlingId === String(order.id) ? " planning-gantt-settling" : "") +
                      (savingDropId === String(order.id) ? " planning-gantt-pending" : "")}
                    data-item-id={String(order.id)} data-caption-end={slot.captionEnd} data-priority={String(request?.priority||'normal')}
                    style={{ top: 8 + slot.track * 60, left: slot.left + "%", width: blockWidth + "%" }}
                    disabled={!can("orders", "view")}
                    draggable={canDragItem(order)}
                    onPointerDown={() => { if (order.planning_locked_at) setError("planningLockedMessage"); }}
                    onDragStart={(event) => { if (!canDragItem(order)) { event.preventDefault(); return; }
                      beginDrag(event,order,event.currentTarget.classList.contains("planning-gantt-block"));event.dataTransfer.setData("text/plain", String(order.id));
                      event.dataTransfer.effectAllowed = "move"; draggingRef.current = String(order.id);
                      lastHoverRef.current = null;
                      setDraggingId(String(order.id)); setError(""); }}
                    onDragEnd={() => finishDrag(String(order.id))}
                    onMouseEnter={event=>{if(!draggingId)showBarTip(event.currentTarget,String(order.id));}}
                    onMouseLeave={()=>setBarTip(null)} onBlur={()=>setBarTip(null)}
                    aria-describedby={barTip?.id===String(order.id)?'planning-bar-tooltip':undefined}
                    onClick={() => {setBarTip(null);openEditor(order);}}
                    onFocus={event=>{if(event.currentTarget.matches(':focus-visible')){const el=event.currentTarget;requestAnimationFrame(()=>showBarTip(el,String(order.id)));}}}
                    aria-label={String(order.code || request?.code) + " · " + localName(productOf(order), lang) +
                      ' · ' + amountOf(order) + ' · ' + t(planningBoardStatus(order)) + ' · ' + t('priority_'+(request?.priority||'normal')) + ' · ' + t('executionPlannedStart') + ': ' + formatTime(order.start_time, lang, zone) +
                      ' · ' + t('executionPlannedFinish') + ': ' + formatTime(order.expected_finish, lang, zone) +
                      (slot.finish?' · '+formatDuration(Math.ceil((slot.finish-slot.start)/60_000),lang):'')+
                      (visualState(order) === 'delayed' ? ' · ' + t('delayed') : '') +
                      (conflicts.has(String(order.id)) ? ' · ' + t('planningOverlap') : '') +
                      (hasRisk ? " · " + t(dueState) : "") +
                      (order.planning_locked_at ? " · " + t("planningLocked") : "")}>
                    <span className="planning-duration-band" aria-hidden="true"/>
                    <MeasuredGanttCode code={String(order.code||request?.code)}/>
                    <span className="planning-job-caption" dir={lang==='ar'?'rtl':'ltr'}>
                     <strong>{warning&&<span className="planning-risk-mark" title={t(warning)} aria-label={t(warning)}>!</span>}<bdi dir="ltr">{String(order.code||request?.code)}</bdi>{!slot.compact&&' · '+localName(productOf(order),lang)}</strong>
                     {!slot.compact&&<small>{amountOf(order)} · {t(planningBoardStatus(order))}{hasRisk?' · '+t(dueState):''}</small>}
                     {slot.compact&&slot.finish!==null&&<small className="planning-caption-time"><bdi dir="ltr">{captionClock.format(slot.start)}–{captionClock.format(slot.finish)}</bdi> · {formatDuration(Math.ceil((slot.finish-slot.start)/60_000),lang)}</small>}
                     {['high','urgent'].includes(String(request?.priority))&&<span className="planning-gantt-priority">↑ {t('priority_'+request?.priority)}</span>}
                     {order.planning_locked_at&&<span className="planning-lock-mark" aria-label={t('planningLocked')}>🔒</span>}
                     {slot.finish===null&&<small>{t('planningUnknownFinish')}</small>}
                    </span>
                  </button>;
                })}
                {layout.unknown.length>0&&<div className="planning-time-unknown" style={{top:8+layout.tracks*60}}>{layout.unknown.map((order:Row)=><button key={String(order.id)} type="button" onClick={()=>openEditor(order)}><bdi>{String(order.code)}</bdi> · {t('planningUnknownBlock')}</button>)}</div>}
                {layout.reservations.map((slot:any) => <MaintenanceTimelineBlock key={slot.reservation.id} schedule={slot.reservation} compact={slot.compact} captionEnd={slot.captionEnd}
                  from={rangeStart} until={rangeEnd} top={8+slot.track*60} t={t} lang={lang} zone={zone}
                  onOpen={() => openMaintenance(slot.reservation.maintenance_request_id)}/>)}
                {linePreview && dragging && Number.isFinite(linePreview.start) && linePreview.durationMs &&
                  <span data-preview-start={linePreview.start} data-preview-finish={linePreview.finish} className={"planning-drag-ghost planning-pointer-ghost" + (linePreview.error ? " planning-drag-ghost-invalid" : "")}
                    style={{ left: position(linePreview.start) + "%", width: widthOf(linePreview.finish - linePreview.start) + "%",
                      ...productStyle(dragging) }}
                    aria-hidden="true"><i className="planning-preview-interval"/>{linePreview.setupMs && <i className="planning-setup-segment"
                      style={{ width: Math.min(100, (finishAfterWorkingMs(linePreview.start, linePreview.setupMs,
                        calendar, zone) - linePreview.start) / (linePreview.finish - linePreview.start) * 100) + "%" }} />}
                    <span className="planning-drag-caption" dir="auto"><bdi>{String(dragging.code)}</bdi> · {formatDuration(Math.ceil((linePreview.finish-linePreview.start)/60_000),lang)}</span></span>}
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
          {independentSchedules.length>0 && <div className="planning-lane">
            <strong className="planning-line-label" dir={lang==='ar' ? 'rtl' : 'ltr'}>{t('mpIndependentMachines')}<small>{t('mpMachineImpact')}</small></strong>
            <div className="planning-lane-track" style={{height:12+independentSchedules.length*60}}>
              {ticks.slice(1,-1).map(tick => <i className="planning-gridline" key={tick} style={{left:position(tick)+'%'}}/>)}
              {independentSchedules.map((schedule,index) => <MaintenanceTimelineBlock key={schedule.id} schedule={schedule}
                from={rangeStart} until={rangeEnd} top={8+index*60} t={t} lang={lang} zone={zone}
                onOpen={() => openMaintenance(schedule.maintenance_request_id)}/>)}
            </div></div>}
        </div>
      </div></div>
    </section>
    <section className="planning-section planning-requests-progressed" aria-labelledby="planning-progressed-title">
      <header><h3 id="planning-progressed-title">{t("planningProgressedTitle")} <span>{progressedItems.length}</span></h3>
        </header>
      <label className="planning-work-sort">{t('planningSort')} <select value={workSort} onChange={e=>setWorkSort(e.target.value)}><option value="start">{t('executionPlannedStart')}</option><option value="required">{t('requiredBy')}</option><option value="reference">{t('planningOrderReference')}</option></select></label>
      {progressedItems.length ? compactTable(sortPlanningRows(progressedItems,requests,workSort),false) :
        <p className="planning-empty">{t("planningScheduleEmpty")}</p>}
    </section>
    </div>
    {editing && !pendingReason && <div className="planning-overlay" onMouseDown={(event) => {
      if (event.target === event.currentTarget) closeEditor();
    }}><aside className="planning-drawer" ref={drawerRef} role="dialog" aria-modal="true" aria-labelledby="planning-editor-title">
      <header><div><small><bdi dir="ltr">{String(editing.code || requestOf(editing)?.code)}</bdi></small>
        <h3 id="planning-editor-title" ref={headingRef} tabIndex={-1}>{t("planningScheduleTitle")}</h3>
        <p className="planning-detail-product" style={productStyle(editing)} dir="auto">
          {localName(productOf(editing), lang)}</p><strong className="planning-detail-quantity">{amountOf(editing)}</strong></div>
        <button type="button" aria-label={t("close")} onClick={closeEditor}>×</button></header>
      <DeliveryContext rows={fulfillment.data?.rows||[]} item={editing.id} t={t} lang={lang} zone={zone}/><p className="planning-detail-status">{t(planningBoardStatus(editing))}{planningTiming(editing,requestOf(editing))&&' · '+t(planningTiming(editing,requestOf(editing))!)}</p>
      {dragReason(editing)&&<p className="planning-warning" role="status">{t(dragReason(editing))}</p>}
      {completionWork.find(w=>w.item_id===editingId)?.held&&<p className="planning-warning" role="alert">{t('planningQualityHold')}</p>}
      <section className="planning-order-summary" aria-label={t('planningOrderReference')}><div className="planning-summary-heading"><strong>{t(editingKind.type)}</strong>{priorityBadge(editing)}</div>
       <dl className="planning-editor-facts"><div><dt>{t('requestOrigin')}</dt><dd>{editingKind.origin?t(editingKind.origin):<RequestOrigin request={requestOf(editing)} t={t} lang={lang} zone={zone}/>}</dd></div>
        <div><dt>{t('requiredBy')}</dt><dd>{requestOf(editing)?.required_by?formatTime(requestOf(editing)?.required_by,lang,zone):t('planningNoRequestedDeadline')}</dd></div></dl>
      </section>
      {isScheduled(editing)&&<p className="planning-saved-interval"><span>{historyLineName(String(editing.line_id))}</span><span>{t('executionPlannedStart')}: <bdi>{formatTime(editing.start_time,lang,zone)}</bdi></span><span>{t('executionPlannedFinish')}: <bdi>{formatTime(editing.expected_finish,lang,zone)}</bdi></span></p>}
      <ProductionExecutionActions props={{snapshot:s,t,lang,can,command,refreshSnapshot}} item={editing} historyOnly />
      {isScheduled(editing)&&<button type="button" className="planning-show-on-timeline" onClick={()=>showSchedule(editing)}>{t('planningShowTimeline')}</button>}
      {editing.planning_locked_at && <p className="planning-lock-detail">{lockInfo(editing)}</p>}
      {editing.planning_locked_at&&canToggleLock(editing) && <button type="button" className="planning-lock-action"
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
        <label className="planning-field"><span>{t("planningPlannedStart")}</span>
          <input type="datetime-local" step="0.001" required value={start} disabled={!editableItem(editing)}
            onChange={(event) => setStart(event.target.value)} /></label>
        <p className="planning-time-basis">{s.factory?.timezone?t('planningFactoryTime'):t('planningTimezoneMissing')}</p>
        {selectedLine && <div className="planning-proposal" role="status">
          <details className="planning-calculation"><summary>{t('planningCalculation')}</summary><span>{t("planningRate")}: <strong>{selectedDuration && !selectedDuration.error
            ? selectedDuration.rate + " " + unitOf(editing) + "/" + t("planningHour") : "—"}</strong></span>
          <span>{t("planningSetupDuration")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(selectedDuration.setupMinutes, lang) : "—"}</strong></span>
          <span>{t("planningProductionDuration")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(Math.ceil(selectedDuration.productionMs / 60_000), lang) : "—"}</strong></span>
          <span>{t("planningTotalWorking")}: <strong>{selectedDuration?.error ? t(selectedDuration.error) :
            selectedDuration ? formatDuration(Math.ceil(selectedDuration.totalMs / 60_000), lang) : "—"}</strong></span>
          {editableItem(editing)&&canSeeResources&&!dragReason(editing)&&<button type="button" className="planning-compare-lines" disabled={busy||!maintenanceReady} onClick={()=>{closeEditor();void findSlots(editing);}}>{t('planningCompareLines')}</button>}
          </details>{proposal&&!proposal.error&&proposal.start!==proposal.requestedStart&&<span>{t("planningPlannedStart")}: <strong>{formatTime(new Date(proposal.start).toISOString(),lang,zone)}</strong></span>}
          {proposal && !proposal.error && proposal.start !== proposal.requestedStart &&
            <span className="planning-warning">{t("planningSnappedStart")}</span>}
          <span>{t("expected_finish")}: <strong>{proposal && !proposal.error
            ? formatTime(new Date(proposal.finish).toISOString(), lang, zone) : t("planningUnknownFinish")}</strong></span>
          {proposal && !proposal.error && requestOf(editing)?.required_by && <span className={deadlineStatus(proposal.finish, requestOf(editing)?.required_by) === "planningLate"
            ? "planning-warning" : ""}>{t(deadlineStatus(proposal.finish, requestOf(editing)?.required_by))}</span>}
        </div>}
        {(requestOf(editing)?.request_type === 'SALES_PRODUCTION' || fulfillment.data?.rows.some(row => row.item_id === String(editing.id) && row.sales_order_id)) &&
          <SalesPlanningGuidance factory={String(s.factory?.id)} item={String(editing.id)} fetchedAt={s.fetchedAt} proposal={proposal} t={t} lang={lang} zone={zone} validateSuggestion={candidate=>{
           const line=availableLines.find((l:Row)=>String(l.id)===candidate.line);if(!line||!maintenanceReady)return 'mpAvailabilityUnknown';
           const check:any=proposeSchedule(editing,line,Date.parse(candidate.start),orders,centers,capabilities,Date.now(),calendar,zone,maintenance);
           return check.error||(check.start!==Date.parse(candidate.start)||check.finish!==Date.parse(candidate.finish)?'planningAvailabilityChanged':!sourceCovers(line,check.start,check.finish)?'mpBoardOutside':null);
          }} checking={maintenanceRead.loading||completionRead.loading} needsTimelineCheck={candidate=>Date.parse(candidate.start)<rangeStart||Date.parse(candidate.finish)>rangeEnd} onInspect={candidate=>{setZoomIndex(3);setViewStart(Date.parse(localDateTimeToUtc(formatLocalInput(candidate.start,zone).slice(0,10)+'T00:00',zone)));}} onChoose={candidate=>{setLineId(candidate.line);setStart(formatLocalInput(candidate.start,zone,true));setError('');}} />}
        {suggestedGaps.length > 0 && <div className="planning-gap-choices">
          <strong>{t("planningEarliestAvailable")}</strong>
          {suggestedGaps.map((gap: { start: number; finish: number; slot: { start: number } }) =>
            <button type="button" className="planning-earliest-choice" key={gap.start} disabled={!maintenanceReady||!editableItem(editing)}
              onClick={() => { setStart(formatLocalInput(new Date(gap.slot.start).toISOString(), zone, true)); setError(""); }}>
              {formatTime(new Date(gap.slot.start).toISOString(), lang, zone)} ·
              {t("planningGapUntil")} {formatTime(new Date(gap.finish).toISOString(), lang, zone)}
            </button>)}
        </div>}
        {editingOriginal&&<details className="planning-support planning-source-details"><summary>{lang==='ar'?'تفاصيل الأمر الأصلي':'Original-order details'}</summary><dl className="planning-editor-facts"><div><dt>{t('planningOriginalOrder')}</dt><dd><bdi>{String(editingOriginal)}</bdi></dd></div></dl></details>}
        {selectedLine && planningWarnings({ ...editing, line_id: lineId,
          start_time: start && Number.isFinite(Date.parse(start)) ? (() => { try { return localDateTimeToUtc(start, zone); } catch { return null; } })() : null }, requestOf(editing), selectedLine,
          centers, capabilities, orders).map((warning) =>
          <p className="planning-warning" key={warning}>{t(warning)}</p>)}
        {error && <p className="planning-warning" role="alert">{t(error)}</p>}
        {proposal?.server_validation_required&&<p className="planning-warning" role="status">{t('mpManualServerValidation')}</p>}
        {proposal?.error && proposal.error !== error &&
          <p className="planning-warning" role="alert">{t(proposal.error)}</p>}
        <div className="planning-actions"><button type="button" onClick={closeEditor}>{t("close")}</button>
          {isScheduled(editing) && <button type="button" disabled={busy || !completionRead.complete || resourceLimited || !editableItem(editing)}
            onClick={() => void unschedule()}>{t("planningUnschedule")}</button>}
          <button className="primary" disabled={busy || !completionRead.complete || resourceLimited || !editableItem(editing) ||
            !canSeeResources || !s.factory?.timezone || !availableLines.length ||
            !proposal || Boolean(proposal.error)}>{t("planningSaveSchedule")}</button></div>
      </form>
      <details className="planning-support"><summary>{t("planningHistory")}</summary><section className="planning-history" aria-label={t("planningHistory")}>
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
      </section></details>
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
          <PlanningExceptionReview key={pendingReason.item+String(pendingReason.planned_start)+String(pendingReason.target_line)} props={{snapshot:s,t,lang,can,command}} pending={pendingReason} reasonCode={reasonCode} note={reasonNote} onNote={setReasonNote} onChange={v=>{policyReview.current=v;}}/>
          {error && <p role="alert" className="planning-warning">{t(error)}</p>}
          <div className="planning-actions">
            <button type="button" disabled={busy} onClick={cancelReason}>{t("cancel")}</button>
            <button type="submit" className="primary" disabled={busy || !reasonCode ||
              (reasonCode === "other" && !reasonNote.trim())}>{t(busy?'updating':'planningSaveRevision')}</button>
          </div>
        </form>
      </div>
    </div>}
    {maintenanceRequest && maintenanceRead.data && <MaintenancePlanningDrawer key={`${maintenanceRequest.id}:${maintenanceRequest.revision}`}
      snapshot={s} t={t} lang={lang} can={can} command={command} request={maintenanceRequest} board={maintenanceRead.data}
      schedule={maintenanceSchedules.find(schedule => schedule.maintenance_request_id===maintenanceRequest.id)}
      onClose={() => setMaintenanceId('')} onChanged={maintenanceRead.reload}/>}
  </section>;
}
