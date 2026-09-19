import { useState } from "react";
import { Field } from "@/components/ui";
import type { Translate } from "@/types";
/** Stored only while a join is in progress; removed once request_membership succeeds. */
const JOIN_CODE_KEY = "factory-join-code";
export default function Authentication({
  t,
  onSuccess,
}: {
  t: Translate;
  onSuccess: () => void;
}) {
  const [mode, setMode] = useState("signin"),
    [busy, setBusy] = useState(false),
    [message, setMessage] = useState(""),
    [joinAccount, setJoinAccount] = useState<"existing" | "new">("existing");
  const stashedCode =
    typeof window === "undefined"
      ? ""
      : window.localStorage.getItem(JOIN_CODE_KEY) || "";
  async function post(path: string, body: unknown) {
    const res = await fetch(path, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    return { ok: res.ok, body: await res.json().catch(() => ({})) };
  }
  async function requestMembership(code: string, email: string) {
    const display = String(email).split("@")[0] || email;
    const { ok, body } = await post("/api/data", {
      command: "request_membership",
      args: { code, display_name: display },
    });
    if (!ok || body.error) {
      setMessage(body.error || "error");
      return false;
    }
    window.localStorage.removeItem(JOIN_CODE_KEY);
    return true;
  }
  async function submit(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    setMessage("");
    const data = Object.fromEntries(new FormData(e.currentTarget));
    const email = String(data.email || ""),
      password = String(data.password || "");
    try {
      if (mode !== "join") {
        const { body } = await post("/api/auth", {
          ...data,
          action: mode,
        });
        if (body.error) setMessage(body.error);
        else if (body.verify) setMessage("verify");
        else onSuccess();
        return;
      }
      const code = String(data.code || "").trim();
      window.localStorage.setItem(JOIN_CODE_KEY, code);
      if (joinAccount === "existing") {
        const { ok, body } = await post("/api/auth", {
          action: "signin",
          email,
          password,
        });
        // Same generic auth error as plain sign-in; never reveals whether the account exists.
        if (!ok || body.error) {
          setMessage(body.error || "authError");
          return;
        }
        if (await requestMembership(code, email)) onSuccess();
        return;
      }
      const signup = await post("/api/auth", {
        action: "signup",
        email,
        password,
      });
      if (!signup.ok || signup.body.error) {
        setMessage(signup.body.error || "authError");
        return;
      }
      const signin = await post("/api/auth", {
        action: "signin",
        email,
        password,
      });
      if (!signin.ok || signin.body.error) {
        // Email confirmation is pending; the stashed code completes the join after sign-in.
        setMessage("verifyJoin");
        return;
      }
      if (await requestMembership(code, email)) onSuccess();
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
        <h2>{t(mode === "join" ? "joinFactory" : mode)}</h2>
        <div className="tabs">
          {(
            [
              ["signin", "signin"],
              ["signup", "createFactory"],
              ["join", "joinFactory"],
            ] as const
          ).map(([key, label]) => (
            <button
              aria-pressed={mode === key}
              onClick={() => {
                setMode(key);
                setMessage("");
              }}
              key={key}
            >
              {t(label)}
            </button>
          ))}
        </div>
        <form onSubmit={submit}>
          <Field label={t("email")}>
            <input
              name="email"
              required
              autoComplete="username"
              autoCapitalize="none"
              autoCorrect="off"
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
          {mode === "signup" && <p className="muted">{t("signupFactoryHelp")}</p>}
          {mode === "join" && (
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
              <div className="tabs">
                <button
                  type="button"
                  aria-pressed={joinAccount === "existing"}
                  onClick={() => setJoinAccount("existing")}
                >
                  {t("hasAccount")}
                </button>
                <button
                  type="button"
                  aria-pressed={joinAccount === "new"}
                  onClick={() => setJoinAccount("new")}
                >
                  {t("newAccountJoin")}
                </button>
              </div>
              <p className="muted">{t("joinHelp")}</p>
            </>
          )}
          {message && (
            <p role="status" className="notice">
              {t(message)}
            </p>
          )}
          <button className="primary" disabled={busy}>
            {t(
              busy
                ? "loading"
                : mode === "join"
                  ? "requestAccess"
                  : mode,
            )}
          </button>
        </form>
      </section>
    </main>
  );
}
