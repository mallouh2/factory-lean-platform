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
}: {
  title: string;
  onClose: () => void;
  children: React.ReactNode;
  t: Translate;
}) {
  return (
    <dialog
      ref={(el) => {
        if (el && !el.open) el.showModal();
      }}
      onCancel={onClose}
      className="dialog"
    >
      <header>
        <h2>{title}</h2>
        <button onClick={onClose} aria-label={t("close")}>
          ×
        </button>
      </header>
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
