import { useEffect, useId, useState } from "react";
import type { Row, Translate, Language } from "@/types";
export function localName(row: Row | undefined | null, lang: Language) {
  return String(
    (lang === "ar" && row?.name_ar) || row?.name || row?.code || "—",
  );
}
export function Badge({ status, t }: { status: string; t: Translate }) {
  return (
    <span className={`badge status-${status}`}>
      <span aria-hidden="true">
        {status === "running"
          ? "▶"
          : status === "stopped"
            ? "■"
            : status === "maintenance"
              ? "⚙"
              : "●"}
      </span>
      {t(status)}
    </span>
  );
}
export function Empty({ t }: { t: Translate }) {
  return (
    <div className="empty">
      <span aria-hidden="true">▧</span>
      <p>{t("noResults")}</p>
    </div>
  );
}
export function Field({
  label,
  children,
}: {
  label: string;
  children: React.ReactNode;
}) {
  return (
    <label className="field">
      <span>{label}</span>
      {children}
    </label>
  );
}
export function Dialog({
  title,
  onClose,
  children,
  t,
  busy = false,
  className = '',
  headerActions,
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  t: Translate;
  busy?: boolean;
  className?: string;
  headerActions?: React.ReactNode;
}) {
  const titleId=useId();
  const [error, setError] = useState("");
  useEffect(() => {
    const handler = (e: Event) => setError((e as CustomEvent).detail);
    window.addEventListener("factory-error", handler);
    return () => window.removeEventListener("factory-error", handler);
  }, []);
  return (
    <dialog
      ref={(el) => {
        if (el && !el.open) el.showModal();
      }}
      onCancel={event => { event.preventDefault(); if (!busy) onClose(); }}
      className={className?`dialog ${className}`:'dialog'}
      aria-labelledby={titleId}
      onKeyDown={event=>{
        if(!className.includes('prv3-dialog')||event.key!=='Tab')return;
        const nodes=[...event.currentTarget.querySelectorAll<HTMLElement>('button,input,select,textarea,a[href],summary')]
          .filter(el=>!el.matches(':disabled')&&el.tabIndex>=0&&el.getClientRects().length>0);
        if(!nodes.length){event.preventDefault();event.currentTarget.focus();return;}
        if(event.shiftKey&&document.activeElement===nodes[0]){event.preventDefault();nodes.at(-1)?.focus();}
        else if(!event.shiftKey&&document.activeElement===nodes.at(-1)){event.preventDefault();nodes[0].focus();}
      }}
    >
      <header>
        <h2 id={titleId}>{title}</h2>
        {headerActions}
        <button disabled={busy} onClick={onClose} aria-label={t("close")}>
          ×
        </button>
      </header>
      {error && (
        <p role="alert" className="toast">
          {t(error)}
        </p>
      )}
      {children}
    </dialog>
  );
}
export function formatTime(value: unknown, lang: Language, zone: string) {
  if (!value) return "—";
  return new Intl.DateTimeFormat(lang, {
    timeZone: zone,
    dateStyle: "medium",
    timeStyle: "short",
  }).format(new Date(String(value)));
}
