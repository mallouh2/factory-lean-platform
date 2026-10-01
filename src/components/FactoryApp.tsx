"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
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
import ProductionOrdersV2 from "@/features/ProductionOrdersV2";
import ProductionPlanning from "@/features/ProductionPlanning";
import PlatformDashboard from "@/features/PlatformDashboard";
import PersonPermissions from "@/features/PersonPermissions";
import DowntimeAnalysis from "@/features/DowntimeAnalysis";
import DowntimeCapture from "@/features/DowntimeCapture";
import Administration from "@/features/Administration";
import { formatTime } from "./ui";
import { previewPermissions, previewPresets } from "@/utils/permission-preview.mjs";
import HistoryLimitWarning from "./HistoryLimitWarning";
// Floor totals and report tabs own their warnings beside the affected values.
const pageHistoryTables: Record<string, string[]> = {
  dashboard: ["production_entries", "downtime_events"],
  downtime: ["downtime_events", "production_transfers"],
};
const primary = [
  "dashboard",
  "lines",
  "orders",
  "planning",
  "products",
  "downtime",
  "reports",
];
const admin = ["employees", "roles", "settings", "support", "audit"];
const future = [
  "warehouse",
  "purchasing",
  "sales",
  "quality",
  "maintenance",
  "lean",
  "safety",
  "costing",
  "hr",
];
const sidebarIconPaths: Record<string, string[]> = {
  platform: ["M3 21h18", "M5 21V7l7-4 7 4v14", "M9 10h.01", "M15 10h.01", "M9 14h.01", "M15 14h.01", "M10 21v-4h4v4"],
  dashboard: ["M3 3h8v8H3z", "M13 3h8v8h-8z", "M3 13h8v8H3z", "M13 13h8v8h-8z"],
  lines: ["M2 9h5v6H2z", "M10 9h5v6h-5z", "M18 9h4v6h-4z", "M7 12h3", "M15 12h3"],
  orders: ["M8 4h8", "M9 3h6v3H9z", "M7 5H5v16h14V5h-2", "M8 11h8", "M8 15h8", "M8 19h5"],
  planning: ["M3 5h18v16H3z", "M3 10h18", "M8 3v4", "M16 3v4", "M7 15h4", "M14 15h3"],
  products: ["M3 7 12 3l9 4v10l-9 4-9-4z", "M3 7l9 4 9-4", "M12 11v10"],
  downtime: ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M10 9v6", "M14 9v6"],
  reports: ["M4 20V10h4v10", "M10 20V5h4v15", "M16 20v-8h4v8", "M3 20h18"],
  employees: ["M9 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8z", "M2 20v-2a7 7 0 0 1 14 0v2", "M17 5a4 4 0 0 1 0 7", "M19 14a6 6 0 0 1 3 5v1"],
  roles: ["M5 4h14v16H5z", "M9 9a2 2 0 1 0 4 0 2 2 0 0 0-4 0z", "M8 16a3 3 0 0 1 6 0", "M16 9h1", "M16 13h1"],
  settings: ["M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M10 2h4l.5 2.3 1.5.7 2-.9 2.8 2.8-.9 2 .7 1.5L23 11v2l-2.4.5-.7 1.5.9 2-2.8 2.8-2-.9-1.5.7L14 22h-4l-.5-2.4-1.5-.7-2 .9-2.8-2.8.9-2-.7-1.5L1 13v-2l2.4-.6.7-1.5-.9-2L6 4.1l2 .9 1.5-.7z"],
  support: ["M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18z", "M12 8a4 4 0 1 0 0 8 4 4 0 0 0 0-8z", "M5.6 5.6 9.2 9.2", "M14.8 14.8l3.6 3.6", "M18.4 5.6l-3.6 3.6", "M9.2 14.8l-3.6 3.6"],
  audit: ["M6 3h9l4 4v14H6z", "M15 3v4h4", "M9 12h7", "M9 16h4", "M16 16l1.5 1.5L20 15"],
  preview: ["M2 12s3.6-6 10-6 10 6 10 6-3.6 6-10 6S2 12 2 12z", "M12 9a3 3 0 1 0 0 6 3 3 0 0 0 0-6z"],
};
function SidebarIcon({ name }: { name: string }) {
  return <svg className="sidebar-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor"
    strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
    {(sidebarIconPaths[name] || sidebarIconPaths.dashboard).map((path, index) => <path key={index} d={path} />)}
  </svg>;
}
export default function FactoryApp() {
  const [lang, setLang] = useState<Language>("en"),
    [dirtyLayout, setDirtyLayout] = useState(false),
    [view, setView] = useState("dashboard"),
    [snapshot, setSnapshot] = useState<Snapshot | null>(null),
    [loading, setLoading] = useState(true),
    [notice, setNotice] = useState(""),
    [mobile, setMobile] = useState(false),
    [sidebarCollapsed, setSidebarCollapsed] = useState(false),
    [preview, setPreview] = useState("full"),
    [lineManagement, setLineManagement] = useState(false),
    [lineManagementMachineId, setLineManagementMachineId] = useState<string | null>(null),
    [supportFactory, setSupportFactory] = useState(""),
    [center, setCenter] = useState<Row | null>(null);
  const [planningItemId, setPlanningItemId] = useState<string | null>(null);
  const [loadNotice, setLoadNotice] = useState("");
  const dictionary: Record<string, string> = lang === "ar" ? ar : en;
  const t = (key: string) => dictionary[key] || key;
  const commandErrorKey = (value: unknown) =>
    typeof value === "string" && Object.hasOwn(dictionary, value) ? value : "error";
  const previewMode = snapshot?.testingPreviewEligible ? preview : "full";
  const visiblePermissions = useMemo(() => snapshot
    ? previewPermissions(snapshot.permissions, previewMode) : [], [snapshot, previewMode]);
  const can = (module: string, action = "view") =>
    Boolean(
      visiblePermissions.includes(
        `${module === "products" || module === "planning" ? "orders" : module}:${action}`,
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
    setSidebarCollapsed(localStorage.getItem("factory-sidebar-collapsed") === "1");
    void load();
    const timer = setInterval(() => {
      if (!document.hidden) void load();
    }, 30000);
    return () => clearInterval(timer);
  }, [load]);
  useEffect(() => {
    if (!snapshot?.factory) return;
    const allowed = (page: string) => visiblePermissions.includes(`${page === "products" || page === "planning" ? "orders" : page}:view`);
    if (!allowed(view)) {
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
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === "ar" ? "rtl" : "ltr";
    localStorage.setItem("factory-language", lang);
  }, [lang]);
  useEffect(() => {
    localStorage.setItem("factory-sidebar-collapsed", sidebarCollapsed ? "1" : "0");
  }, [sidebarCollapsed]);
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
  const props = snapshot ? { snapshot: previewMode === "full" ? snapshot : { ...snapshot, permissions: visiblePermissions }, t, lang, command, can } : null;
  const previewHome = can("dashboard") ? "dashboard" : [...primary, ...admin].find((page) => can(page)) || "dashboard";
  const navigate = (x: string) => {
    if (previewMode !== "full" && !can(x)) return;
    if (dirtyLayout && !confirm(t("discardChanges"))) return;
    setView(x);
    if (x !== "planning") setPlanningItemId(null);
    setLineManagement(false);
    setMobile(false);
    setNotice("");
  };
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
    setView("dashboard");
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
        <div className={`app-shell${sidebarCollapsed ? " nav-collapsed" : ""}`}>
          {mobile && (
            <button
              className="nav-backdrop"
              aria-label={t("close")}
              onClick={() => setMobile(false)}
            />
          )}
          <aside className={`sidebar ${mobile ? "is-open" : ""}`}>
            <button className="sidebar-toggle" title={t(sidebarCollapsed ? "expandNavigation" : "collapseNavigation")}
              aria-label={t(sidebarCollapsed ? "expandNavigation" : "collapseNavigation")}
              aria-expanded={!sidebarCollapsed}
              onClick={() => setSidebarCollapsed(!sidebarCollapsed)}>
              {sidebarCollapsed ? "»" : "«"}
            </button>
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
                  setView("dashboard");
                }}
              >
                <SidebarIcon name="platform" /><span className="nav-label">{t("platformDashboard")}</span>
              </button>
            )}
            <div className="nav-section-label">{t("operations")}</div>
            <nav aria-label={t("operations")}>
              {primary.map(
                (x) =>
                  can(x) && (
                    <button
                      key={x}
                      className={view === x ? "nav-active" : ""}
                      title={t(x)}
                      aria-label={t(x)}
                      onClick={() => navigate(x)}
                    >
                      <SidebarIcon name={x} />
                      <span className="nav-label">{t(x)}</span>
                      {x === "downtime" && (
                        <small>
                          {snapshot.tables.downtime_events?.filter(
                            (e) => !e.ended_at,
                          ).length || 0}
                        </small>
                      )}
                    </button>
                  ),
              )}
            </nav>
            <div className="nav-section-label">{t("administration")}</div>
            <nav aria-label={t("administration")}>
              {admin.map(
                (x) =>
                  can(x) && (
                    <button
                      key={x}
                      className={view === x ? "nav-active" : ""}
                      title={t(x)}
                      aria-label={t(x)}
                      onClick={() => navigate(x)}
                    >
                      <SidebarIcon name={x} />
                      <span className="nav-label">{t(x)}</span>
                    </button>
                  ),
              )}
            </nav>
            <details className="future">
              <summary>{t("roadmap")}</summary>
              {future.map((x) => (
                <div key={x}>
                  {t(x)}
                  <small>{t("later")}</small>
                </div>
              ))}
            </details>
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
          <div className="workspace">
            <header className="topbar">
              <button
                className="menu-button"
                aria-label={t("menu")}
                aria-expanded={mobile}
                onClick={() => setMobile(!mobile)}
              >
                ☰
              </button>
              <div>
                <p className="breadcrumb">{String(snapshot.factory.name)}</p>
                <h1>{t(view)}</h1>
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
              {snapshot.factory.is_demo && (
                <div className="demo-banner">{t("demo")}</div>
              )}
              {can(view) && <HistoryLimitWarning snapshot={snapshot}
                tables={pageHistoryTables[view] || []} t={t} />}
              {notice && (
                <div
                  role="status"
                  className={`toast ${notice === "saved" ? "success" : ""}`}
                >
                  <span>{t(notice)}</span>
                  <button onClick={() => setNotice("")} aria-label={t("close")}>
                    ×
                  </button>
                </div>
              )}
              {props &&
                (can(view) ? (
                  view === "dashboard" ? (
                    <Dashboard
                      {...props}
                      onCenter={setCenter}
                      onNavigate={navigate}
                    />
                  ) : view === "downtime" ? (
                    <>
                      <DowntimeCapture {...props} />
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
                          setLineManagement(true);
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
                        <summary>{t("permissionTemplates")}</summary>
                        <Administration {...props} view="roles" />
                      </details>
                    </>
                  ) : view === "orders" ? (
                    <ProductionOrdersV2 {...props} onPlanItem={(itemId) => {
                      setPlanningItemId(itemId); setView("planning");
                    }} />
                  ) : view === "planning" ? (
                    <ProductionPlanning key={planningItemId || "planning"} {...props} initialItemId={planningItemId} />
                  ) : primary.includes(view) ? (
                    <Configuration key={view} {...props} view={view} />
                  ) : (
                    <Administration key={view} {...props} view={view} />
                  )
                ) : (
                  <div className="panel">{t("noPermission")}</div>
                ))}
            </main>
          </div>
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
