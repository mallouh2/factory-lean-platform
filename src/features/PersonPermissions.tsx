import { useState } from "react";
import type { FeatureProps } from "./types";
import { Field, localName } from "@/components/ui";
export default function PersonPermissions({
  snapshot: s,
  t,
  lang,
  command,
  can,
}: FeatureProps) {
  const [person, setPerson] = useState(""),
    [selected, setSelected] = useState<string[]>([]),
    [visual, setVisual] = useState(false),
    [busy, setBusy] = useState(false);
  const modules = [
    ...new Set((s.tables.permissions || []).map((p) => String(p.module))),
  ];
  const actions = ["view", "create", "edit", "delete", "approve", "export"];
  const members = s.tables.memberships || [];
  const group = (m: string) =>
    [
      "dashboard",
      "lines",
      "centers",
      "machine_status",
      "orders",
      "downtime",
      "reports",
    ].includes(m)
      ? "productionGroup"
      : "administration";
  return (
    <section className="panel">
      <h2>{t("personPermissions")}</h2>
      <p>{t("personPermissionsHelp")}</p>
      <label className="check">
        <input
          type="checkbox"
          checked={visual}
          onChange={(e) => setVisual(e.target.checked)}
        />
        {t("permissionVisualization")}
      </label>
      {visual && (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>{t("employees")}</th>
                {modules.map((m) => (
                  <th key={m}>{t(m)}</th>
                ))}
              </tr>
            </thead>
            <tbody>
              {members.map((u) => (
                <tr key={String(u.id)}>
                  <th>{String(u.display_name)}</th>
                  {modules.map((m) => {
                    const grants = (s.tables.user_permissions || []).filter(
                      (p) => p.user_id === u.user_id && p.module === m,
                    );
                    return (
                      <td
                        key={m}
                        className={
                          grants.length ? `permission-${group(m)}` : ""
                        }
                      >
                        <span>{grants.length ? "✓" : "—"}</span>
                        <small>
                          {grants.map((p) => t(String(p.action))).join(" · ")}
                        </small>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      <Field label={t("employee")}>
        <select
          value={person}
          onChange={(e) => {
            setPerson(e.target.value);
            setSelected(
              (s.tables.user_permissions || [])
                .filter((p) => p.user_id === e.target.value)
                .map((p) => `${p.module}:${p.action}`),
            );
          }}
        >
          <option value="">{t("chooseEmployee")}</option>
          {members
            .filter((m) => !m.is_owner)
            .map((m) => (
              <option key={String(m.id)} value={String(m.user_id)}>
                {String(m.display_name)}
              </option>
            ))}
        </select>
      </Field>
      {person && (
        <>
          <Field label={t("applyTemplate")}>
            <select
              key={person}
              defaultValue=""
              disabled={!can("roles", "edit")}
              onChange={(e) => {
                if (e.target.value)
                  setSelected(
                    (s.tables.role_permissions || [])
                      .filter((p) => p.role_id === e.target.value)
                      .map((p) => `${p.module}:${p.action}`),
                  );
              }}
            >
              <option value="">{t("optionalTemplate")}</option>
              {(s.tables.roles || []).map((r) => (
                <option key={String(r.id)} value={String(r.id)}>
                  {localName(r, lang)}
                </option>
              ))}
            </select>
          </Field>
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>{t("module")}</th>
                  {actions.map((a) => (
                    <th key={a}>{t(a)}</th>
                  ))}
                </tr>
              </thead>
              <tbody>
                {modules.map((m) => (
                  <tr
                    key={m}
                    className={visual ? `permission-${group(m)}` : ""}
                  >
                    <th>{t(m)}</th>
                    {actions.map((a) => {
                      const key = `${m}:${a}`;
                      return (
                        <td key={a}>
                          <input
                            type="checkbox"
                            aria-label={`${t(m)} ${t(a)}`}
                            disabled={!can("roles", "edit") || !can(m, a)}
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
            disabled={busy || !can("roles", "edit")}
            onClick={async () => {
              setBusy(true);
              try {
                await command("set_user_permissions", {
                  factory: s.factory?.id,
                  person,
                  permissions: selected.map((x) => {
                    const [module, action] = x.split(":");
                    return { module, action };
                  }),
                });
              } catch {
              } finally {
                setBusy(false);
              }
            }}
          >
            {t("savePersonPermissions")}
          </button>
        </>
      )}
    </section>
  );
}
