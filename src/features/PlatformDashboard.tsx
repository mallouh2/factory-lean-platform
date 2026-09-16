import { useState } from "react";
import type { FeatureProps } from "./types";
import { Field, formatTime } from "@/components/ui";
export default function PlatformDashboard({
  snapshot: s,
  t,
  lang,
  command,
  onOpen,
}: FeatureProps & { onOpen: (id: string) => Promise<void> }) {
  const [search, setSearch] = useState(""),
    [creating, setCreating] = useState(false),
    [busy, setBusy] = useState(false);
  return (
    <main className="platform-page">
      <header className="section-head">
        <div>
          <p className="eyebrow">{t("platformAdmin")}</p>
          <h1>{t("platformDashboard")}</h1>
        </div>
        <button className="primary" onClick={() => setCreating(!creating)}>
          + {t("createFactory")}
        </button>
      </header>
      <input
        aria-label={t("search")}
        placeholder={t("search")}
        value={search}
        onChange={(e) => setSearch(e.target.value)}
      />
      {creating && (
        <form
          className="panel"
          onSubmit={async (e) => {
            e.preventDefault();
            setBusy(true);
            const f = new FormData(e.currentTarget);
            try {
              const id = await command("create_factory", {
                name: f.get("name"),
                timezone: f.get("timezone"),
                industry: f.get("industry"),
              });
              await onOpen(String(id));
            } catch {
            } finally {
              setBusy(false);
            }
          }}
        >
          <Field label={t("factoryName")}>
            <input name="name" required minLength={2} maxLength={120} />
          </Field>
          <Field label={t("industry")}>
            <input name="industry" maxLength={120} />
          </Field>
          <Field label={t("timezone")}>
            <select name="timezone" defaultValue="Asia/Qatar">
              {Intl.supportedValuesOf("timeZone").map((z) => (
                <option key={z}>{z}</option>
              ))}
            </select>
          </Field>
          <button className="primary" disabled={busy}>
            {t("createFactory")}
          </button>
        </form>
      )}
      <div className="factory-grid">
        {s.factories
          ?.filter((f) =>
            `${f.name} ${f.id}`.toLowerCase().includes(search.toLowerCase()),
          )
          .map((f) => (
            <article className="panel" key={String(f.id)}>
              <span className="brand-symbol">▥</span>
              <h2>{String(f.name)}</h2>
              <small className="code">{String(f.id)}</small>
              <p>{t(String(f.status))}</p>
              <dl className="detail-grid">
                {["users", "lines", "machines"].map((k) => (
                  <div key={k}>
                    <dt>{t(k)}</dt>
                    <dd>{String(f[k])}</dd>
                  </div>
                ))}
              </dl>
              <p>
                {t("lastActivity")}:{" "}
                {formatTime(f.last_activity, lang, String(f.timezone))}
              </p>
              <button
                className="primary"
                disabled={busy}
                onClick={async () => {
                  setBusy(true);
                  try {
                    await onOpen(String(f.id));
                  } finally {
                    setBusy(false);
                  }
                }}
              >
                {t("openFactory")}
              </button>
            </article>
          ))}
      </div>
    </main>
  );
}
