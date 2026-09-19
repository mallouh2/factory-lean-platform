import { useEffect, useRef, useState } from "react";
import { Field } from "@/components/ui";
import type { FeatureProps } from "./types";
/** Shared with the landing join form; cleared only after request_membership succeeds. */
const JOIN_CODE_KEY = "factory-join-code";
/** One automatic join attempt per code per browser session, surviving remounts. */
const JOIN_ATTEMPT_KEY = "factory-join-attempt";
export default function Onboarding({ snapshot, t, command }: FeatureProps) {
  const [tab, setTab] = useState("createFactory");
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const autoJoinInFlight = useRef(false);
  const stashedCode =
    typeof window === "undefined"
      ? ""
      : window.localStorage.getItem(JOIN_CODE_KEY) || "";
  useEffect(() => {
    if (autoJoinInFlight.current || snapshot.membership || !stashedCode)
      return;
    if (window.sessionStorage.getItem(JOIN_ATTEMPT_KEY) === stashedCode)
      return;
    autoJoinInFlight.current = true;
    window.sessionStorage.setItem(JOIN_ATTEMPT_KEY, stashedCode);
    const display = String(snapshot.user.email || "").split("@")[0] || "member";
    command("request_membership", {
      code: stashedCode,
      display_name: display,
    })
      .then(() => {
        window.localStorage.removeItem(JOIN_CODE_KEY);
        window.sessionStorage.removeItem(JOIN_ATTEMPT_KEY);
      })
      .catch((error) => {
        autoJoinInFlight.current = false;
        setTab("joinFactory");
        setNotice(error instanceof Error ? error.message : "error");
      });
  }, [snapshot.membership, snapshot.user.email, stashedCode, command]);
  if (snapshot.membership)
    return (
      <section className="onboarding panel">
        <h1>{t(String(snapshot.membership.status))}</h1>
        <p>
          {t(
            snapshot.membership.status === "rejected"
              ? "rejectedHelp"
              : "pendingHelp",
          )}
        </p>
      </section>
    );
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const data = new FormData(e.currentTarget);
    const logo = data.get("logo");
    data.delete("logo");
    const form = Object.fromEntries(data);
    // Browser-detected zone first; the established project default only when detection fails.
    const timezone =
      Intl.DateTimeFormat().resolvedOptions().timeZone || "Asia/Qatar";
    try {
      const factoryId = await command(
        tab === "createFactory" ? "create_factory" : "request_membership",
        tab === "createFactory" ? { ...form, timezone } : form,
      );
      if (tab === "createFactory" && factoryId) {
        window.localStorage.removeItem(JOIN_CODE_KEY);
        if (logo instanceof File && logo.size) {
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
            timezone,
            logo: result.path,
          });
        }
      }
      if (tab === "joinFactory") window.localStorage.removeItem(JOIN_CODE_KEY);
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
          </>
        ) : (
          <>
            <Field label={t("joinCode")}>
              <input
                name="code"
                required
                maxLength={20}
                dir="ltr"
                defaultValue={stashedCode}
              />
            </Field>
            <Field label={t("displayName")}>
              <input
                name="display_name"
                minLength={2}
                maxLength={100}
                required
              />
            </Field>
            {notice && (
              <p role="status" className="notice">
                {t(notice)}
              </p>
            )}
          </>
        )}
        <button className="primary" disabled={busy}>
          {t(tab === "createFactory" ? "createFactory" : "requestAccess")}
        </button>
      </form>
    </section>
  );
}
