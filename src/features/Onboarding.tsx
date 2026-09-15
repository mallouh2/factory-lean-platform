import { useState } from "react";
import { Field } from "@/components/ui";
import type { FeatureProps } from "./types";
export default function Onboarding({ snapshot, t, command }: FeatureProps) {
  const [tab, setTab] = useState("createFactory");
  const [busy, setBusy] = useState(false);
  if (snapshot.membership)
    return (
      <section className="onboarding panel">
        <h1>{t(String(snapshot.membership.status))}</h1>
        <p>{t("pendingHelp")}</p>
      </section>
    );
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const form = Object.fromEntries(new FormData(e.currentTarget));
    try {
      await command(
        tab === "createFactory" ? "create_factory" : "join_factory",
        form,
      );
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="onboarding panel">
      <h1>{t("onboarding")}</h1>
      <div className="tabs">
        {["createFactory", "joinFactory"].map((x) => (
          <button aria-pressed={tab === x} onClick={() => setTab(x)} key={x}>
            {t(x)}
          </button>
        ))}
      </div>
      <form onSubmit={submit}>
        {tab === "createFactory" ? (
          <>
            <Field label={t("factoryName")}>
              <input name="name" required minLength={2} maxLength={120} />
            </Field>
            <Field label={t("industry")}>
              <input name="industry" required maxLength={120} />
            </Field>
            <Field label={t("timezone")}>
              <select name="timezone" defaultValue="Asia/Qatar">
                {Intl.supportedValuesOf("timeZone").map((x) => (
                  <option key={x}>{x}</option>
                ))}
              </select>
            </Field>
          </>
        ) : (
          <>
            <Field label={t("joinCode")}>
              <input name="code" required maxLength={20} dir="ltr" />
            </Field>
            <Field label={t("displayName")}>
              <input
                name="display_name"
                minLength={2}
                maxLength={100}
                required
              />
            </Field>
          </>
        )}
        <button className="primary" disabled={busy}>
          {t(tab === "createFactory" ? "createFactory" : "requestAccess")}
        </button>
      </form>
    </section>
  );
}
