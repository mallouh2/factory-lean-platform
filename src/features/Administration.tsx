import { localDateTimeToUtc } from "@/utils/manufacturing.mjs";
import { useState } from "react";
import type { FeatureProps } from "./types";
import { Field, Empty, localName, formatTime } from "@/components/ui";
import Configuration from "./Configuration";
export default function Administration({
  view,
  ...props
}: FeatureProps & { view: string }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [joinCode, setJoinCode] = useState(""),
    [role, setRole] = useState(""),
    [selected, setSelected] = useState<string[]>([]),
    [busy, setBusy] = useState(false);
  const [search, setSearch] = useState(""),
    [membershipFilter, setMembershipFilter] = useState("all"),
    [supportMode, setSupportMode] = useState("disabled");
  const [localError, setLocalError] = useState("");
  const safeCommand: typeof command = (...args) =>
    command(...args).catch(() => "");
  const factory = s.factory!;
  const zone = String(factory.timezone);
  async function settings(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    try {
      const form = new FormData(e.currentTarget);
      let logo = factory.logo_path;
      const file = form.get("logo");
      if (file instanceof File && file.size) {
        const upload = new FormData();
        upload.set("factory", String(factory.id));
        upload.set("file", file);
        const r = await fetch("/api/logo", { method: "POST", body: upload });
        const b = await r.json();
        if (!r.ok) throw new Error(t("error"));
        logo = b.path;
      }
      await safeCommand("update_settings", {
        factory: factory.id,
        name: form.get("name"),
        timezone: form.get("timezone"),
        logo,
      });
    } catch {
      setLocalError("error");
    } finally {
      setBusy(false);
    }
  }
  if (view === "settings")
    return (
      <section className="panel narrow">
        <h2>{t("settings")}</h2>
        {localError && (
          <p role="alert" className="toast">
            {t(localError)}
          </p>
        )}
        <form onSubmit={(e) => void settings(e).catch(() => {})}>
          <Field label={t("factoryName")}>
            <input
              name="name"
              defaultValue={String(factory.name)}
              required
              minLength={2}
              maxLength={120}
            />
          </Field>
          <Field label={t("timezone")}>
            <select name="timezone" defaultValue={zone}>
              {Intl.supportedValuesOf("timeZone").map((x) => (
                <option key={x}>{x}</option>
              ))}
            </select>
          </Field>
          <Field label={t("logo")}>
            <input
              name="logo"
              type="file"
              accept="image/png,image/jpeg,image/webp"
            />
          </Field>
          <button
            className="primary"
            disabled={busy || !can("settings", "edit")}
          >
            {t("save")}
          </button>
        </form>
        <hr />
        <h3>{t("joinCode")}</h3>
        <code className="join-code">{joinCode || "••••••••••"}</code>
        <div className="row-actions">
          <button
            disabled={!can("settings", "edit")}
            onClick={async () =>
              setJoinCode(
                String(
                  await safeCommand("get_join_code", { factory: factory.id }),
                ),
              )
            }
          >
            {t("view")}
          </button>
          <button
            disabled={!can("settings", "edit")}
            onClick={async () => {
              if (confirm(t("confirmRegenerate")))
                setJoinCode(
                  String(
                    await safeCommand("get_join_code", {
                      factory: factory.id,
                      regenerate: true,
                    }),
                  ),
                );
            }}
          >
            {t("regenerate")}
          </button>
        </div>
        <p className="muted">
          {t("factoryId")}: {String(factory.id)}
        </p>
      </section>
    );
  if (view === "employees")
    return (
      <section className="panel">
        <header className="section-head">
          <h2>{t("employees")}</h2>
          <input
            aria-label={t("search")}
            placeholder={t("search")}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />
        </header>
        <div className="tabs">
          {["all", "pending", "approved", "rejected"].map((status) => (
            <button
              key={status}
              aria-pressed={membershipFilter === status}
              onClick={() => setMembershipFilter(status)}
            >
              {t(status)} ·{" "}
              {
                (s.tables.memberships || []).filter(
                  (m) => status === "all" || m.status === status,
                ).length
              }
            </button>
          ))}
        </div>
        {!s.tables.memberships?.length ? (
          <Empty t={t} />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  {["name", "status", "role", "action"].map((x) => (
                    <th key={x}>{t(x)}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {s.tables.memberships
                  .filter(
                    (m) =>
                      (membershipFilter === "all" ||
                        m.status === membershipFilter) &&
                      String(m.display_name)
                        .toLowerCase()
                        .includes(search.toLowerCase()),
                  )
                  .map((member) => (
                    <tr key={String(member.id)}>
                      <td>
                        <strong>{String(member.display_name)}</strong>
                        <small className="cell-note code">
                          {String(member.user_id)}
                        </small>
                      </td>
                      <td>{t(String(member.status))}</td>
                      <td>
                        {member.is_owner
                          ? t("owner")
                          : localName(
                              s.tables.roles?.find(
                                (r) => r.id === member.role_id,
                              ),
                              lang,
                            )}
                      </td>
                      <td>
                        {!member.is_owner && can("employees", "approve") && (
                          <form
                            className="row-actions"
                            onSubmit={async (e) => {
                              e.preventDefault();
                              const form = new FormData(e.currentTarget);
                              await safeCommand("manage_member", {
                                factory: factory.id,
                                id: member.id,
                                role: form.get("role"),
                                status: "approved",
                              });
                            }}
                          >
                            <select
                              name="role"
                              aria-label={t("role")}
                              required
                              defaultValue={String(member.role_id || "")}
                            >
                              <option value="">{t("role")}</option>
                              {s.tables.roles?.map((r) => (
                                <option key={String(r.id)} value={String(r.id)}>
                                  {localName(r, lang)}
                                </option>
                              ))}
                            </select>
                            <button type="submit">{t("approve")}</button>
                            <button
                              type="button"
                              onClick={() => {
                                if (confirm(t("reject") + "?"))
                                  void safeCommand("manage_member", {
                                    factory: factory.id,
                                    id: member.id,
                                    role: member.role_id,
                                    status: "rejected",
                                  });
                              }}
                            >
                              {t("reject")}
                            </button>
                          </form>
                        )}
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>
        )}
      </section>
    );
  if (view === "roles")
    return (
      <>
        <section className="panel">
          <h2>{t("roles")}</h2>
          <p className="muted">{t("permissionsHelp")}</p>
          <Field label={t("role")}>
            <select
              value={role}
              onChange={(e) => {
                setRole(e.target.value);
                setSelected(
                  (s.tables.role_permissions || [])
                    .filter((p) => p.role_id === e.target.value)
                    .map((p) => p.module + ":" + p.action),
                );
              }}
            >
              <option value="">{t("role")}</option>
              {s.tables.roles?.map((r) => (
                <option key={String(r.id)} value={String(r.id)}>
                  {localName(r, lang)}
                </option>
              ))}
            </select>
          </Field>
          {role && (
            <>
              <div className="table-wrap">
                <table>
                  <thead>
                    <tr>
                      <th>{t("module")}</th>
                      {[
                        "view",
                        "create",
                        "edit",
                        "delete",
                        "approve",
                        "export",
                      ].map((a) => (
                        <th key={a}>{t(a)}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {[
                      "dashboard",
                      "factory",
                      "lines",
                      "centers",
                      "machine_status",
                      "orders",
                      "downtime",
                      "reports",
                      "employees",
                      "roles",
                      "settings",
                      "support",
                      "audit",
                    ].map((m) => (
                      <tr key={m}>
                        <th>{t(m)}</th>
                        {[
                          "view",
                          "create",
                          "edit",
                          "delete",
                          "approve",
                          "export",
                        ].map((a) => {
                          const key = m + ":" + a;
                          return (
                            <td key={a}>
                              <input
                                aria-label={t(m) + " " + t(a)}
                                type="checkbox"
                                disabled={!can("roles", "edit")}
                                checked={selected.includes(key)}
                                onChange={(e) =>
                                  setSelected(
                                    e.target.checked
                                      ? [...selected, key]
                                      : selected.filter((x) => x !== key),
                                  )
                                }
                              />
                            </td>
                          );
                        })}
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
              <button
                className="primary"
                disabled={!can("roles", "edit")}
                onClick={() =>
                  void safeCommand("set_permissions", {
                    factory: factory.id,
                    role,
                    permissions: selected.map((x) => {
                      const [module, action] = x.split(":");
                      return { module, action };
                    }),
                  })
                }
              >
                {t("save")}
              </button>
            </>
          )}
        </section>
        <Configuration view="roles" {...props} />
      </>
    );
  if (view === "support")
    return (
      <section className="panel narrow">
        <h2>{t("support")}</h2>
        <p>{t("supportHelp")}</p>
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            const f = new FormData(e.currentTarget);
            await safeCommand("set_support_by_email", {
              factory: factory.id,
              email: f.get("email"),
              role: f.get("role"),
              mode: f.get("mode"),
              expires_at: f.get("expires_at")
                ? localDateTimeToUtc(String(f.get("expires_at")), zone)
                : null,
            });
          }}
        >
          <Field label={t("supportUser")}>
            <input name="email" type="email" required maxLength={254} />
          </Field>
          <Field label={t("role")}>
            <select name="role" required>
              {s.tables.roles?.map((r) => (
                <option key={String(r.id)} value={String(r.id)}>
                  {localName(r, lang)}
                </option>
              ))}
            </select>
          </Field>
          <Field label={t("status")}>
            <select
              name="mode"
              value={supportMode}
              onChange={(e) => setSupportMode(e.target.value)}
            >
              {["disabled", "temporary", "permanent"].map((x) => (
                <option key={x} value={x}>
                  {t(x)}
                </option>
              ))}
            </select>
          </Field>
          <Field label={t("expires") + ` (${zone})`}>
            <input
              name="expires_at"
              type="datetime-local"
              required={supportMode === "temporary"}
              disabled={supportMode !== "temporary"}
            />
          </Field>
          <button className="primary" disabled={!s.membership?.is_owner}>
            {t("save")}
          </button>
        </form>
        {s.tables.support_access?.map((x) => (
          <div className="support-grant" key={String(x.id)}>
            <code>{String(x.user_id)}</code>
            <strong>{t(String(x.mode))}</strong>
            <span>{formatTime(x.expires_at, lang, zone)}</span>
          </div>
        ))}
      </section>
    );
  return (
    <section className="panel">
      <header className="section-head">
        <h2>{t("audit")}</h2>
        <input
          aria-label={t("search")}
          placeholder={t("search")}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
      </header>
      <div className="table-wrap">
        <table>
          <thead>
            <tr>
              {[
                "time",
                "userId",
                "action",
                "entity",
                "oldValue",
                "newValue",
              ].map((x) => (
                <th key={x}>{t(x)}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {s.tables.audit_logs
              ?.filter((x) =>
                JSON.stringify(x).toLowerCase().includes(search.toLowerCase()),
              )
              .map((x) => (
                <tr key={String(x.id)}>
                  <td>{formatTime(x.created_at, lang, zone)}</td>
                  <td>
                    {String(
                      s.tables.memberships?.find(
                        (m) => m.user_id === x.actor_id,
                      )?.display_name ||
                        x.actor_id ||
                        "—",
                    )}
                  </td>
                  <td>{String(x.action)}</td>
                  <td>{String(x.entity)}</td>
                  <td>
                    <details>
                      <summary>{t("view")}</summary>
                      <pre>{JSON.stringify(x.old_data, null, 2)}</pre>
                    </details>
                  </td>
                  <td>
                    <details>
                      <summary>{t("view")}</summary>
                      <pre>{JSON.stringify(x.new_data, null, 2)}</pre>
                    </details>
                  </td>
                </tr>
              ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}
