"use client";
import { useCallback, useEffect, useState } from "react";
import en from "@/locales/en.json";
import ar from "@/locales/ar.json";
import type { Language, Row, Snapshot } from "@/types";
import Authentication from "@/features/Authentication";
import Onboarding from "@/features/Onboarding";
import Dashboard from "@/features/Dashboard";
import CenterDetails from "@/features/CenterDetails";
import Configuration from "@/features/Configuration";
import Reports from "@/features/Reports";
import Administration from "@/features/Administration";
import { formatTime } from "./ui";
const primary = [
  "dashboard",
  "factory",
  "lines",
  "centers",
  "orders",
  "downtime",
  "reports",
];
const admin = ["employees", "roles", "settings", "support", "audit"];
const future = [
  "planning",
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
const icons: Record<string, string> = {
  dashboard: "▦",
  factory: "▥",
  lines: "≡",
  centers: "⚙",
  orders: "▤",
  downtime: "◷",
  reports: "▥",
  employees: "♙",
  roles: "⌘",
  settings: "⚙",
  support: "◉",
  audit: "▧",
};
export default function FactoryApp() {
  const [lang, setLang] = useState<Language>("en"),
    [view, setView] = useState("dashboard"),
    [snapshot, setSnapshot] = useState<Snapshot | null>(null),
    [loading, setLoading] = useState(true),
    [notice, setNotice] = useState(""),
    [mobile, setMobile] = useState(false),
    [center, setCenter] = useState<Row | null>(null);
  const dictionary: Record<string, string> = lang === "ar" ? ar : en;
  const t = (key: string) => dictionary[key] || key;
  const can = (module: string, action = "view") =>
    Boolean(snapshot?.permissions.includes(`${module}:${action}`));
  const load = useCallback(async () => {
    try {
      const res = await fetch("/api/data", { cache: "no-store" });
      if (res.status === 401) {
        setSnapshot(null);
        return;
      }
      const body = await res.json();
      if (!res.ok) {
        setNotice(body.error || "error");
        return;
      }
      setSnapshot(body);
    } catch {
      setNotice("dataWarning");
    } finally {
      setLoading(false);
    }
  }, []);
  useEffect(() => {
    setLang(localStorage.getItem("factory-language") === "ar" ? "ar" : "en");
    void load();
    const timer = setInterval(() => {
      if (!document.hidden) void load();
    }, 30000);
    return () => clearInterval(timer);
  }, [load]);
  useEffect(() => {
    document.documentElement.lang = lang;
    document.documentElement.dir = lang === "ar" ? "rtl" : "ltr";
    localStorage.setItem("factory-language", lang);
  }, [lang]);
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
        setNotice(body.error || "error");
        throw new Error(body.error);
      }
      setNotice("saved");
      await load();
      return body.data;
    } catch (error) {
      setNotice("error");
      throw error;
    }
  }
  const props = snapshot ? { snapshot, t, lang, command, can } : null;
  const navigate = (x: string) => {
    setView(x);
    setMobile(false);
    setNotice("");
  };
  async function signout() {
    if (!confirm(t("logoutConfirm"))) return;
    await fetch("/api/auth", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: "signout" }),
    });
    setSnapshot(null);
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
          {props && <Onboarding {...props} />}
        </>
      ) : (
        <div className="app-shell">
          <aside className={`sidebar ${mobile ? "is-open" : ""}`}>
            <a className="brand" href="#" onClick={() => navigate("dashboard")}>
              <span className="brand-symbol">▥</span>
              <span>
                {t("brand")}
                <small>{String(snapshot.factory.name)}</small>
              </span>
            </a>
            <div className="nav-section-label">{t("operations")}</div>
            <nav aria-label={t("operations")}>
              {primary.map(
                (x) =>
                  can(x) && (
                    <button
                      key={x}
                      className={view === x ? "nav-active" : ""}
                      onClick={() => navigate(x)}
                    >
                      <span aria-hidden="true">{icons[x]}</span>
                      {t(x)}
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
                      onClick={() => navigate(x)}
                    >
                      <span aria-hidden="true">{icons[x]}</span>
                      {t(x)}
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
              <div>
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
              {snapshot.factory.is_demo && (
                <div className="demo-banner">{t("demo")}</div>
              )}
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
                      <Reports {...props} view={view} />
                      {can("downtime", "create") && (
                        <Configuration {...props} view="downtime" />
                      )}
                    </>
                  ) : view === "reports" ? (
                    <Reports {...props} view={view} />
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
