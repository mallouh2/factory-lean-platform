import { useState } from "react";
import { Field } from "@/components/ui";
import type { Translate } from "@/types";
export default function Authentication({
  t,
  onSuccess,
}: {
  t: Translate;
  onSuccess: () => void;
}) {
  const [mode, setMode] = useState("signin"),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState("");
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    const data = Object.fromEntries(new FormData(e.currentTarget));
    try {
      const res = await fetch("/api/auth", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ ...data, action: mode }),
      });
      const body = await res.json();
      if (body.error) setMessage(body.error);
      else if (body.verify) setMessage("verify");
      else onSuccess();
    } catch {
      setMessage("error");
    } finally {
      setBusy(false);
    }
  }
  return (
    <main className="auth">
      <section className="auth-story">
        <div className="brandmark">▥</div>
        <p className="eyebrow">{t("brand")}</p>
        <h1>{t("welcome")}</h1>
        <p>{t("welcomeText")}</p>
        <div className="status-samples">
          {["running", "stopped", "setup"].map((x) => (
            <span key={x} className={`badge status-${x}`}>
              {t(x)}
            </span>
          ))}
        </div>
      </section>
      <section className="auth-card">
        <h2>{t(mode)}</h2>
        <form onSubmit={submit}>
          <Field label={t("email")}>
            <input
              name="email"
              required
              autoComplete="username"
              maxLength={254}
            />
          </Field>
          <Field label={t("password")}>
            <input
              name="password"
              type="password"
              minLength={8}
              maxLength={128}
              required
              autoComplete={
                mode === "signup" ? "new-password" : "current-password"
              }
            />
          </Field>
          {message && (
            <p role="status" className="notice">
              {t(message)}
            </p>
          )}
          <button className="primary" disabled={busy}>
            {t(busy ? "loading" : mode)}
          </button>
        </form>
        <button
          className="text-button"
          onClick={() => {
            setMode(mode === "signin" ? "signup" : "signin");
            setMessage("");
          }}
        >
          {t(mode === "signin" ? "signup" : "signin")}
        </button>
      </section>
    </main>
  );
}
