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
    const data = new FormData(e.currentTarget);
    const logo = data.get("logo");
    data.delete("logo");
    const form = Object.fromEntries(data);
    try {
      const factoryId = await command(
        tab === "createFactory" ? "create_factory" : "request_membership",
        form,
      );
      if (
        tab === "createFactory" &&
        factoryId &&
        logo instanceof File &&
        logo.size
      ) {
        const upload = new FormData();
        upload.set("factory", String(factoryId));
        upload.set("file", logo);
        const response = await fetch("/api/logo", {
          method: "POST",
          body: upload,
        });
        const result = await response.json();
        if (!response.ok) throw new Error("logoError");
        await command("update_settings", {
          factory: factoryId,
          name: form.name,
          timezone: form.timezone,
          logo: result.path,
        });
      }
    } catch (error) {
      window.dispatchEvent(
        new CustomEvent("factory-error", {
          detail: error instanceof Error ? error.message : "error",
        }),
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
            <Field label={t("logo")}>
              <input
                name="logo"
                type="file"
                accept="image/png,image/jpeg,image/webp"
              />
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
