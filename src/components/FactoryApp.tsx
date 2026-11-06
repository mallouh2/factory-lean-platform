"use client";
import {MaterialPreparationWindow} from '@/features/MaterialPreparation';
import ManufacturedOutputExplorer from '@/features/ManufacturedOutputExplorer';
import type {OutputDestination} from '@/features/types';
import {outputDestinationAllowed} from '@/utils/output-navigation.mjs';

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import en from "@/locales/en.json";
import ar from "@/locales/ar.json";
import type { Language, Row, Snapshot } from "@/types";
import Authentication from "@/features/Authentication";
import Onboarding from "@/features/Onboarding";
import Dashboard from "@/features/Dashboard";
import CenterDetails from "@/features/CenterDetails";
import Configuration from "@/features/Configuration";
import Reports from "@/features/Reports";
import LineBuilder from "@/features/LineBuilder";
import FactoryFloorV2 from "@/features/FactoryFloorV2";
import UnfinishedProducts from '@/features/UnfinishedProducts';
import SalesOrders from '@/features/SalesOrders';
import Warehouse from '@/features/Warehouse';
import ProductionOrdersV2 from "@/features/ProductionOrdersV2";
import ProductionCorrections from "@/features/ProductionCorrections";
import {useCorrectionPending} from '@/hooks/useCorrectionPending';
import ProductionRecording from "@/features/ProductionRecording";
import ProductionPlanning from "@/features/ProductionPlanning";
import PlatformDashboard from "@/features/PlatformDashboard";
import PersonPermissions from "@/features/PersonPermissions";
import DowntimeAnalysis from "@/features/DowntimeAnalysis";
import DowntimeCapture from "@/features/DowntimeCapture";
import Maintenance from '@/features/Maintenance';
import LeanAnalysis from '@/features/LeanAnalysis';
import Quality, { QualityNotifications } from '@/features/Quality';
import Purchasing from '@/features/Purchasing';
import Products from '@/features/Products';
import MaterialFlow from '@/features/MaterialFlow';
import Suppliers from '@/features/Suppliers';
import Administration from "@/features/Administration";
import { formatTime } from "./ui";
import { permissionModule, previewPermissions, previewPresets } from "@/utils/permission-preview.mjs";
import HistoryLimitWarning from "./HistoryLimitWarning";
import SidebarIcon from './NavigationIcon';
import OperationalNavigation from './OperationalNavigation';
import { useNavigationOverlay } from './useNavigationOverlay';
// Floor totals and report tabs own their warnings beside the affected values.
const pageHistoryTables: Record<string, string[]> = {
  dashboard: ["production_entries", "downtime_events"],
  downtime: ["downtime_events", "production_transfers"],
};
const primary = [
  "sales",
  "warehouse",
  "purchasing",
  "myPurchaseRequests",
  "lines",
  "orders",
  "productionHistory",
  "planning",
  "products",
  "downtime",
  "maintenance",
  "lean",
  "quality",
  "reports",
];
const admin = ["employees", "roles", "suppliers", "settings", "support", "audit"];
export default function FactoryApp() {
  const [lang, setLang] = useState<Language>("en"),
    [dirtyLayout, setDirtyLayout] = useState(false),
    [view, setView] = useState("lines"),
    [snapshot, setSnapshot] = useState<Snapshot | null>(null),
    [loading, setLoading] = useState(true),
    [notice, setNotice] = useState(""),
    [mobile, setMobile] = useState(false),
    [sidebarCollapsed, setSidebarCollapsed] = useState(true),
    [preview, setPreview] = useState("full"),
    [lineManagement, setLineManagement] = useState(false),
    [lineManagementMachineId, setLineManagementMachineId] = useState<string | null>(null),
    [supportFactory, setSupportFactory] = useState(""),
    [center, setCenter] = useState<Row | null>(null);
  const [outputDestination,setOutputDestination]=useState<OutputDestination|null>(null);
  useEffect(()=>setOutputDestination(null),[snapshot?.factory?.id]);
  const [planningItemId, setPlanningItemId] = useState<string | null>(null);
  const [loadNotice, setLoadNotice] = useState("");
  const [languageLoaded, setLanguageLoaded] = useState(false);
  const [downtimeEventId,setDowntimeEventId] = useState<string | null>(null);
  const navigationOverlay = useNavigationOverlay(mobile, setMobile, setSidebarCollapsed);
  const dictionary: Record<string, string> = lang === "ar" ? ar : en;
  const t = (key: string) => dictionary[key] || key;
  const commandErrorKey = (value: unknown) =>
    typeof value === "string" && Object.hasOwn(dictionary, value) ? value : "error";
  const previewMode = snapshot?.testingPreviewEligible ? preview : "full";
  const visiblePermissions = useMemo(() => snapshot
    ? previewPermissions(snapshot.permissions, previewMode) : [], [snapshot, previewMode]);
  const can = (module: string, action = "view") =>
    Boolean(
      (module === 'myPurchaseRequests' && action === 'view' && snapshot?.membership?.status === 'approved' && visiblePermissions.includes('factory:view')) ||
      (module === 'suppliers' && action === 'view' && visiblePermissions.includes('suppliers:edit')) ||
      (module === 'maintenance' && action === 'view' && snapshot?.membership?.status === 'approved'
        && visiblePermissions.includes('factory:view')) || visiblePermissions.includes(
        `${permissionModule(module)}:${action}`,
      ),
    );
  const load = useCallback(async () => {
    try {
      const res = await fetch(
        "/api/data" +
          (supportFactory
            ? "?factory=" + encodeURIComponent(supportFactory)
            : ""),
        { cache: "no-store" },
      );
      if (res.status === 401) {
        setSnapshot(null);
        setPreview("full");
        setLoadNotice("");
        return;
      }
      const body = await res.json();
      if (!res.ok) {
        if (res.status === 403) setSnapshot(null);
        setLoadNotice(commandErrorKey(body.error));
        return;
      }
      setSnapshot(body);
      setLoadNotice("");
    } catch {
      setLoadNotice("dataWarning");
    } finally {
      setLoading(false);
    }
  }, [supportFactory]);
  useEffect(() => {
    setLang(localStorage.getItem("factory-language") === "ar" ? "ar" : "en");
    setLanguageLoaded(true);
  }, []);
  useEffect(() => {
    void load();
    const timer = setInterval(() => {
      if (!document.hidden) void load();
    }, 30000);
    return () => clearInterval(timer);
  }, [load]);
  useEffect(() => {
    const restore = () => {
      const state=window.history.state,known=[...primary,...admin,'lines','productionHistory','productionCorrections'];
      const requested=new URLSearchParams(window.location.search).get('view');
      setView(state&&known.includes(state.factoryLeanView)?state.factoryLeanView:requested&&known.includes(requested)?requested:'lines');
      setHistoryOpen(state?.factoryLeanHistory===true);
      setHistoryMode(state?.historyMode==='quality'?'quality':'production');
      setLineManagement(state?.lineManagement===true);
      setWarehouseSection(state?.warehouseSection==='requests'?'requests':'inventory');
      if(!state?.factoryLeanHistory)requestAnimationFrame(()=>window.scrollTo(0,historyScroll.current));
    };
    restore();
    window.addEventListener('popstate', restore);
    return () => window.removeEventListener('popstate', restore);
  }, []);
  useEffect(() => {
    if (!snapshot?.factory) return;
    const allowed = (page: string) => can(page);
    if (!allowed(view) && view !== 'productionHistory') {
      const first = [...primary, ...admin].find(allowed);
      if (first) setView(first);
    }
  }, [snapshot, view, visiblePermissions]);
  useEffect(() => {
    const handler = (e: Event) => setNotice((e as CustomEvent).detail);
    window.addEventListener("factory-error", handler);
    return () => window.removeEventListener("factory-error", handler);
  }, []);
  useEffect(() => {
    if (!languageLoaded) return;
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === "ar" ? "rtl" : "ltr";
    localStorage.setItem("factory-language", lang);
  }, [lang, languageLoaded]);
  useEffect(() => {
    if (notice !== 'saved') return;
    const timer = setTimeout(() => setNotice(current => current === 'saved' ? '' : current), 3000);
    return () => clearTimeout(timer);
  }, [notice]);
  async function command(command: string, args: Record<string, unknown>) {
    setNotice("");
    try {
      const r = await fetch("/api/data", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ command, args }),
      });
      const body = await r.json();
      if (!r.ok) {
        throw new Error(commandErrorKey(body.error));
      }
      setNotice("saved");
      await load();
      return body.data;
    } catch (error) {
      const key = commandErrorKey(error instanceof Error ? error.message : null);
      setNotice(key);
      window.dispatchEvent(
        new CustomEvent("factory-error", {
          detail: key,
        }),
      );
      throw new Error(key);
    }
  }
  const props = snapshot ? { snapshot: previewMode === "full" ? snapshot : { ...snapshot, permissions: visiblePermissions }, t, lang, command, can,
    onLanguageChange:()=>setLang(value=>value==='en'?'ar':'en'),refreshSnapshot:load,
    onOutputRelated:(d:OutputDestination)=>{if(outputDestinationAllowed(d,String(snapshot.factory?.id||''),can))setOutputDestination(d);},
    onProductionHistoryOpen:(mode:'production'|'quality'='production')=>{if(!can(mode==='quality'?'quality':'orders'))return;historyScroll.current=window.scrollY;setHistoryMode(mode);setHistoryOpen(true);const url=new URL(window.location.href);url.searchParams.set('view','productionHistory');window.history.replaceState({...window.history.state,factoryLeanView:view},'',window.location.href);window.history.pushState({factoryLeanView:view,factoryLeanHistory:true,historyMode:mode},'',url);} } : null;
  const previewHome = can("lines") ? "lines" : [...primary, ...admin].find((page) => can(page)) || "lines";
  const [correctionRevision,setCorrectionRevision]=useState(0);
  const correctionPending=useCorrectionPending(String(snapshot?.factory?.id||''),snapshot?.user.id||'',can('orders','view')&&can('orders','approve'),String(snapshot?.fetchedAt)+'|'+view+'|'+correctionRevision);
  const [historyOpen,setHistoryOpen]=useState(false),[historyMode,setHistoryMode]=useState<'production'|'quality'>('production');
  const [warehouseSection,setWarehouseSection]=useState<'inventory'|'requests'>('inventory');
  const historyScroll=useRef(0);
  const navigate = (x: string, warehouseWorkspace?:'inventory'|'requests') => {
    x = x === "dashboard" ? "lines" : x === "unfinishedProducts" ? "warehouse" : x === "materialRequests" ? "orders" : x;
    if (previewMode !== "full" && !can(x)) return false;
    if (dirtyLayout && !confirm(t("discardChanges"))) return false;
    setSidebarCollapsed(true);
    setMobile(false);
    if(x==='productionHistory'&&view!=='productionHistory'){props?.onProductionHistoryOpen?.();return;}
    setHistoryOpen(false);
    const url = new URL(window.location.href);
    url.searchParams.set('view', x);
    const nextWarehouse=warehouseWorkspace||warehouseSection;
    window.history.replaceState({...window.history.state,factoryLeanView:view,lineManagement,warehouseSection},'',window.location.href);
    if (url.href !== window.location.href || (x==='warehouse'&&nextWarehouse!==warehouseSection))
      window.history.pushState({factoryLeanView:x,warehouseSection:nextWarehouse}, '', url);
    if(warehouseWorkspace)setWarehouseSection(warehouseWorkspace);
    setView(x);
    if (x !== "planning") setPlanningItemId(null);
    setLineManagement(false);
    setMobile(false);
    setNotice("");
    return true;
  };
  useEffect(() => {
    const open = (event: Event) => {
      if (!can('downtime')) return;
      setDowntimeEventId(String((event as CustomEvent).detail));navigate('downtime');
    };
    window.addEventListener('factory-downtime-open',open);
    return () => window.removeEventListener('factory-downtime-open',open);
  });
  const changePreview = (next: string) => {
    if (dirtyLayout && !confirm(t("discardChanges"))) return;
    setPreview(next);
    setCenter(null);
    setLineManagement(false);
    setNotice("");
  };
  async function openFactory(id: string) {
    await command("open_platform_factory", { factory: id });
    setSupportFactory(id);
    setView("lines");
  }
  async function signout() {
    if (!confirm(t("logoutConfirm"))) return;
    await fetch("/api/auth", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "signout" }),
    });
    setSnapshot(null);
    setSupportFactory("");
    setPreview("full");
  }
  return (
    <>
      <div className="language-control">
        <button
          onClick={() => setLang(lang === "en" ? "ar" : "en")}
          aria-label={lang === "en" ? "العربية" : "English"}
        >
          {lang === "en" ? "العربية" : "English"}
        </button>
      </div>
      {loadNotice && <div role="alert" className="toast">
        <span>{t(loadNotice)}</span>
        <button onClick={() => void load()}>{t("refresh")}</button>
      </div>}
      {loading ? (
        <div className="loading-screen" role="status">
          <div className="loader" />
          <p>{t("loading")}</p>
        </div>
      ) : !snapshot ? (
        <Authentication t={t} onSuccess={() => void load()} />
      ) : !snapshot.factory ? (
        <>
          <button className="onboarding-signout" onClick={() => void signout()}>
            {t("signout")}
          </button>
          {notice && (
            <div role="alert" className="toast">
              {t(notice)}
            </div>
          )}
          {snapshot.supportFactories?.some(
            (x) =>
              x.mode !== "disabled" &&
              (x.mode === "permanent" ||
                Date.parse(String(x.expires_at)) > Date.now()),
          ) && (
            <section className="onboarding panel">
              <h2>{t("support")}</h2>
              {snapshot.supportFactories
                .filter(
                  (x) =>
                    x.mode !== "disabled" &&
                    (x.mode === "permanent" ||
                      Date.parse(String(x.expires_at)) > Date.now()),
                )
                .map((x) => (
                  <button
                    key={String(x.id)}
                    onClick={() => setSupportFactory(String(x.factory_id))}
                  >
                    {t("openFactory")} · {String(x.factory_id).slice(0, 8)}
                  </button>
                ))}
            </section>
          )}
          {props &&
            (snapshot.platformAdmin ? (
              <PlatformDashboard {...props} onOpen={openFactory} />
            ) : (
              <Onboarding {...props} />
            ))}
        </>
      ) : (
        <div className="app-shell">
          {mobile && (
            <button
              className="nav-backdrop"
              aria-label={t("close")}
              onClick={() => setMobile(false)}
            />
          )}
          <aside id="factory-navigation" ref={navigationOverlay.sidebarRef}
            className={`sidebar${!sidebarCollapsed ? ' is-expanded' : ''}${mobile ? ' is-open' : ''}`}
            role={mobile ? 'dialog' : undefined} aria-modal={mobile || undefined} aria-label={t('menu')}
            onPointerEnter={navigationOverlay.onPointerEnter} onPointerLeave={navigationOverlay.onPointerLeave}
            onScroll={navigationOverlay.onScroll}
            onFocusCapture={navigationOverlay.onFocusCapture} onBlurCapture={navigationOverlay.onBlurCapture}
            onKeyDown={navigationOverlay.onKeyDown}>
            <button
              className="sidebar-close"
              aria-label={t("close")}
              onClick={() => setMobile(false)}
            >
              ×
            </button>
            <a className="brand" href="#" title={t(previewHome)}
              aria-label={t(previewHome)} onClick={(event) => {
              event.preventDefault();
              navigate(previewHome);
            }}>
              {snapshot.factory.logo_path ? (
                <img
                  className="factory-logo"
                  src={`/api/logo?factory=${snapshot.factory.id}`}
                  alt={t("factoryLogo")}
                />
              ) : (
                <span className="brand-symbol">▥</span>
              )}
              <span className="brand-copy">
                {t("brand")}
                <small>{String(snapshot.factory.name)}</small>
              </span>
            </a>
            {snapshot.platformAdmin && previewMode === "full" && (
              <button
                className="platform-nav-link"
                title={t("platformDashboard")}
                aria-label={t("platformDashboard")}
                onClick={() => {
                  if(dirtyLayout&&!confirm(t("discardChanges")))return;
                  setSupportFactory("");
                  setView("lines");
                }}
              >
                <SidebarIcon name="platform" /><span className="nav-label">{t("platformDashboard")}</span>
              </button>
            )}
            <button className="sidebar-toggle" type="button" aria-label={t(sidebarCollapsed?'expandNavigation':'collapseNavigation')}
              aria-expanded={!sidebarCollapsed} aria-controls="factory-navigation" onClick={()=>setSidebarCollapsed(value=>!value)}>
              <span aria-hidden="true">{sidebarCollapsed?'»':'«'}</span><span className="nav-label">{t('collapseNavigation')}</span>
            </button>
            <OperationalNavigation can={can} t={t} expanded={!sidebarCollapsed||mobile} onExpand={()=>setSidebarCollapsed(false)}
              active={historyOpen?'productionHistory':view==='lines'?(lineManagement?'manageLinesMachines':'floor'):view==='productionCorrections'?'orders':view==='warehouse'?(warehouseSection==='requests'?'warehouseRequests':'warehouse'):view}
              onNavigate={destination=>{if(destination==='manageLinesMachines'){if(can('lines','edit')||can('centers','edit')||can('lines','create')||can('centers','create')){if(navigate('lines'))setLineManagement(true);}return;}if(destination==='warehouse'||destination==='warehouseRequests'){navigate('warehouse',destination==='warehouse'?'inventory':'requests');}else navigate(destination==='floor'?'lines':destination);}}/>
            {snapshot.testingPreviewEligible && <div className="sidebar-preview">
              <label htmlFor="testing-view-as">{t("viewAs")}</label>
              <select id="testing-view-as" value={previewMode} onChange={(event) => changePreview(event.target.value)}
                aria-describedby="testing-view-as-help">
                {Object.keys(previewPresets).map((key) => <option key={key} value={key}>{t(`preview_${key}`)}</option>)}
              </select>
              <small id="testing-view-as-help">{t("viewAsHelp")}</small>
              <button className="sidebar-preview-expand" type="button" title={t("viewAs")}
                aria-label={t("viewAs")} onClick={() => setSidebarCollapsed(false)}>
                <SidebarIcon name="preview" />
              </button>
            </div>}
            <footer className="sidebar-footer">
              <div className="avatar">
                {String(
                  snapshot.membership?.display_name ||
                    snapshot.user.email ||
                    "",
                )
                  .slice(0, 1)
                  .toUpperCase()}
              </div>
              <div className="sidebar-account-copy">
                <strong>
                  {String(
                    snapshot.membership?.display_name || snapshot.user.email,
                  )}
                </strong>
                <small>
                  {snapshot.membership?.is_owner ? t("owner") : t("account")}
                </small>
              </div>
              <button
                onClick={() => void signout()}
                title={t("signout")}
                aria-label={t("signout")}
              >
                ↪
              </button>
            </footer>
          </aside>
          <div className="workspace" inert={mobile||undefined}>
            <header className="topbar">
              <button
                className="menu-button"
                aria-label={t("menu")}
                aria-expanded={mobile}
                aria-controls="factory-navigation"
                ref={navigationOverlay.menuRef}
                onClick={() => setMobile(!mobile)}
              >
                ☰
              </button>
              <div>
                <p className="breadcrumb">{String(snapshot.factory.name)}</p>
                <h1>{t(historyOpen?'productionHistory':view === 'lines' && !lineManagement ? 'floor' : view)}</h1>
              </div>
              <div className="topbar-actions">
                <span className="updated">
                  {t("updated")}
                  <time>
                    {formatTime(
                      snapshot.fetchedAt,
                      lang,
                      String(snapshot.factory.timezone),
                    )}
                  </time>
                </span>
                <button onClick={() => void load()} aria-label={t("refresh")}>
                  ↻
                </button>
              </div>
            </header>
            <main className="main-content">
              {previewMode !== "full" && <div className="preview-indicator" role="status">
                <span>{t("previewing")}: <strong>{t(`preview_${previewMode}`)}</strong></span>
                <button type="button" onClick={() => changePreview("full")}>{t("exitPreview")}</button>
              </div>}
              {can(view) && <HistoryLimitWarning snapshot={snapshot}
                tables={pageHistoryTables[view] || []} t={t} />}
              {notice && (
                <div
                  role={notice === 'saved' ? 'status' : 'alert'}
                  className={notice === 'saved' ? 'save-toast' : 'toast'}
                >
                  <span>{t(notice)}</span>
                  <button onClick={() => setNotice("")} aria-label={t("close")}>
                    ×
                  </button>
                </div>
              )}
              {historyOpen&&props&&<ProductionRecording {...props} surface="history" historyMode={historyMode} onHistoryBack={()=>window.history.back()}/>}
              <div hidden={historyOpen}>{props &&
                (can(view) ? (
                  view === 'quality' ? <Quality key={String(snapshot.factory.id)} {...props}/> : view === 'lean' ? <><div className="module-navigation">{can('downtime')&&<button onClick={()=>navigate('downtime')}><SidebarIcon name="downtime"/>{t('downtime')}</button>}</div><LeanAnalysis key={String(snapshot.factory.id)} {...props}/></> : view === 'maintenance' ? <Maintenance key={String(snapshot.factory.id)} {...props} /> : view === 'purchasing' ? <Purchasing key={String(snapshot.factory.id)} {...props}/> : view === 'myPurchaseRequests' ? <Purchasing key={String(snapshot.factory.id)} {...props} mine/> : view === 'suppliers' ? <Suppliers key={String(snapshot.factory.id)} {...props}/> : view === 'products' ? <Products key={String(snapshot.factory.id)} {...props}/> : view === 'materialRequests' ? <MaterialFlow key={String(snapshot.factory.id)} {...props}/> : view === 'sales' ? <SalesOrders {...props} /> : view === 'warehouse' ? <Warehouse key={String(snapshot.factory.id)} {...props} initialWorkspace={warehouseSection} /> : view === "unfinishedProducts" ? (<UnfinishedProducts {...props} />) : view === "dashboard" ? (
                    <Dashboard
                      {...props}
                      onCenter={setCenter}
                      onNavigate={navigate}
                    />
                  ) : view === "downtime" ? (
                    <>
                      {can('lean')&&<button className="module-navigation-back" onClick={()=>navigate('lean')}>{t('back')} · {t('lean')}</button>}
                      <DowntimeCapture {...props} initialEventId={downtimeEventId} onReferenceClose={() => setDowntimeEventId(null)} />
                      <details className="panel"><summary>{t("impactRankedDowntime")}</summary>
                        <DowntimeAnalysis {...props} />
                      </details>
                    </>
                  ) : view === "reports" ? (
                    <Reports {...props} view={view} />
                  ) : view === "lines" ? (
                    !lineManagement ? (
                      <FactoryFloorV2
                        {...props}
                        onManage={(machineId) => {
                          setLineManagementMachineId(machineId || null);
                          if(can('lines','edit')||can('centers','edit')||can('lines','create')||can('centers','create'))setLineManagement(true);
                        }}
                      />
                    ) : (
                      <div className="line-management">
                        {!lineManagementMachineId && <button className="line-management-back" onClick={() => {
                          if (dirtyLayout && !confirm(t("discardChanges"))) return;
                          setLineManagement(false);
                        }}><span className="line-management-back-icon" aria-hidden="true">←</span> {t("backToFactoryFloor")}</button>}
                        <LineBuilder {...props} initialMachineId={lineManagementMachineId}
                          onBackToFloor={() => setLineManagement(false)} onDirtyChange={setDirtyLayout} />
                      </div>
                    )
                  ) : view === "roles" ? (
                    <>
                      <PersonPermissions {...props} />
                      <details className="panel">
                        <summary>{t("packageLegacyTemplates")}</summary>
                        <Administration {...props} view="roles" />
                      </details>
                    </>
                  ) : view === "orders" || view === "productionCorrections" ? (
                    <><div className="pc-production-tabs" role="group" aria-label={t('production')}><button aria-pressed={view==='orders'} onClick={()=>navigate('orders')}>{t('orders')}</button>{(can('orders','edit')||can('orders','approve'))&&<button className={correctionPending!==null?'pc-needs-approval':undefined} aria-pressed={view==='productionCorrections'} onClick={()=>navigate('productionCorrections')}>{t('productionCorrections')}{correctionPending!==null&&<span className="pc-pending-count" aria-label={t('pcStatus_PENDING')}> {correctionPending.toLocaleString(lang)} · {t('pcStatus_PENDING')}</span>}</button>}</div>{view==='productionCorrections'?<ProductionCorrections {...props} onChanged={()=>setCorrectionRevision(value=>value+1)}/>:<>{can('orders','edit')&&<details className="planning-support"><summary>{t('materialPreparationWindow')}</summary><MaterialPreparationWindow props={props}/></details>}<QualityNotifications {...props} onPlanItem={itemId=>{setPlanningItemId(itemId);setView('planning');}}/><ProductionOrdersV2 {...props} onPlanItem={(itemId) => {
                      setPlanningItemId(itemId); setView("planning");
                    }} /></>}</>
                  ) : view === "productionHistory" ? (
                    <ProductionRecording {...props} surface="history" onHistoryBack={()=>navigate('lines')}/>
                  ) : view === "planning" ? (
                    <ProductionPlanning key={planningItemId || "planning"} {...props} initialItemId={planningItemId} />
                  ) : primary.includes(view) ? (
                    <Configuration key={view} {...props} view={view} />
                  ) : (
                    <Administration key={view} {...props} view={view} />
                  )
                ) : (
                  <div className="panel">{t("noPermission")}</div>
                ))}</div>
            </main>
          </div>
          {outputDestination&&props&&outputDestination.factory===String(snapshot?.factory?.id||'')&&<ManufacturedOutputExplorer {...props} key={JSON.stringify(outputDestination)} target={outputDestination} onClose={()=>setOutputDestination(null)} onSchedule={id=>{setOutputDestination(null);setPlanningItemId(id);setView('planning');}}/>}
          {center && props && (
            <CenterDetails
              {...props}
              center={center}
              onClose={() => setCenter(null)}
            />
          )}
        </div>
      )}
    </>
  );
}
