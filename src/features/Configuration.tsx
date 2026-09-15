import CenterCapabilities from "./CenterCapabilities";
import {
  formatLocalInput,
  localDateTimeToUtc,
} from "@/utils/manufacturing.mjs";
import { useState } from "react";
import { Dialog, Empty, Field, Badge, localName } from "@/components/ui";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
const config: Record<string, { table: string; fields: string[] }> = {
  factory: { table: "areas", fields: ["name", "name_ar"] },
  lines: {
    table: "production_lines",
    fields: ["name", "name_ar", "code", "area_id"],
  },
  centers: {
    table: "work_centers",
    fields: [
      "name",
      "name_ar",
      "code",
      "type",
      "area_id",
      "line_id",
      "order_id",
      "operator_id",
      "start_time",
      "expected_finish",
      "parent_id",
      "production_speed",
      "default_cycle_time",
      "current_cycle_time",
      "planned_capacity",
      "position",
      "description",
      "notes",
    ],
  },
  orders: {
    table: "production_orders",
    fields: [
      "code",
      "product_id",
      "line_id",
      "status",
      "target_quantity",
      "start_time",
      "expected_finish",
    ],
  },
  downtime: {
    table: "downtime_reasons",
    fields: ["name", "name_ar", "parent_id", "requires_description"],
  },
  products: {
    table: "products",
    fields: [
      "name",
      "name_ar",
      "code",
      "category",
      "unit",
      "diameter",
      "length",
      "color",
      "weight",
      "standard_rate",
    ],
  },
  roles: { table: "roles", fields: ["name", "name_ar"] },
};
const relations: Record<string, string> = {
  area_id: "areas",
  line_id: "production_lines",
  order_id: "production_orders",
  operator_id: "memberships",
  product_id: "products",
  parent_id: "downtime_reasons",
};
const numbers = [
  "diameter",
  "length",
  "weight",
  "standard_rate",
  "production_speed",
  "default_cycle_time",
  "current_cycle_time",
  "planned_capacity",
  "position",
  "target_quantity",
  "produced_quantity",
  "rejected_quantity",
];
export default function Configuration({
  view,
  ...props
}: FeatureProps & { view: string }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [editing, setEditing] = useState<Row | null>(null),
    [search, setSearch] = useState(""),
    [busy, setBusy] = useState(false),
    [targetOrder, setTargetOrder] = useState<Row | null>(null);
  const c = config[view];
  const permissionModule = view === "products" ? "orders" : view;
  const zone = String(s.factory?.timezone || "UTC");
  const relatedTable = (field: string) =>
    field === "parent_id" && view === "centers"
      ? "work_centers"
      : relations[field];
  if (!c) return null;
  const rows = (s.tables[c.table] || []).filter(
    (x) =>
      !x.archived &&
      (localName(x, lang) + " " + x.code)
        .toLowerCase()
        .includes(search.toLowerCase()),
  );
  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const f = new FormData(e.currentTarget),
      payload: Record<string, unknown> = {};
    for (const field of c.fields) {
      const value = String(f.get(field) || "");
      payload[field] =
        field === "requires_description"
          ? f.has(field)
          : numbers.includes(field)
            ? value === ""
              ? null
              : Number(value)
            : relations[field]
              ? value || null
              : ["start_time", "expected_finish"].includes(field)
                ? value
                  ? localDateTimeToUtc(value, zone)
                  : null
                : value;
    }
    try {
      await command("save_record", {
        factory: s.factory?.id,
        resource: view,
        id: editing?.id || null,
        payload,
      });
      setEditing(null);
    } catch {
      // Keep the form open so the user can correct the input.
    } finally {
      setBusy(false);
    }
  }
  async function archive(row: Row) {
    if (confirm(t("confirmArchive")))
      await command("save_record", {
        factory: s.factory?.id,
        resource: view,
        id: row.id,
        payload: { archived: true },
      });
  }
  return (
    <section className="panel">
      <header className="section-head">
        <input
          aria-label={t("search")}
          placeholder={t("search")}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {can(permissionModule, "create") && (
          <button className="primary" onClick={() => setEditing({})}>
            + {t("add")}
          </button>
        )}
      </header>
      {!rows.length ? (
        <Empty t={t} />
      ) : (
        <div className="table-wrap">
          <table>
            <thead>
              <tr>
                <th>{t(view === "orders" ? "code" : "name")}</th>
                <th>{t("code")}</th>
                <th>{t(view === "orders" ? "achievement" : "status")}</th>
                <th>{t("action")}</th>
              </tr>
            </thead>
            <tbody>
              {rows.map((row) => (
                <tr key={String(row.id)}>
                  <td>
                    <strong>
                      {view === "orders"
                        ? String(row.code)
                        : localName(row, lang)}
                    </strong>
                    {view === "centers" && (
                      <small className="cell-note">{t(String(row.type))}</small>
                    )}
                  </td>
                  <td className="code">{String(row.code || "—")}</td>
                  <td>
                    {row.status ? (
                      <>
                        <Badge status={String(row.status)} t={t} />
                        {view === "orders" && (
                          <div className="order-progress">
                            <progress
                              value={Number(row.produced_quantity)}
                              max={Number(row.target_quantity)}
                            />
                            <span>
                              {String(row.produced_quantity)} /{" "}
                              {String(row.target_quantity)}
                            </span>
                          </div>
                        )}
                      </>
                    ) : (
                      "—"
                    )}
                  </td>
                  <td>
                    <div className="row-actions">
                      {view === "orders" && can("orders", "edit") && (
                        <button onClick={() => setTargetOrder(row)}>
                          {t("dailyTarget")}
                        </button>
                      )}
                      {can(permissionModule, "edit") && (
                        <button onClick={() => setEditing(row)}>
                          {t("edit")}
                        </button>
                      )}
                      {["factory", "lines", "centers"].includes(view) &&
                        can(permissionModule, "delete") && (
                          <button
                            onClick={() => void archive(row).catch(() => {})}
                          >
                            {t("archive")}
                          </button>
                        )}
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {targetOrder && (
        <Dialog
          t={t}
          title={t("dailyTarget")}
          onClose={() => setTargetOrder(null)}
        >
          <form
            onSubmit={async (e) => {
              e.preventDefault();
              const f = new FormData(e.currentTarget);
              setBusy(true);
              try {
                await command("set_daily_target", {
                  factory: s.factory?.id,
                  production_order: targetOrder.id,
                  day: f.get("day"),
                  target: Number(f.get("target")),
                });
                setTargetOrder(null);
              } catch {
              } finally {
                setBusy(false);
              }
            }}
          >
            <Field label={t("day")}>
              <input
                name="day"
                type="date"
                required
                defaultValue={formatLocalInput(
                  new Date().toISOString(),
                  zone,
                ).slice(0, 10)}
              />
            </Field>
            <Field label={t("productionTarget")}>
              <input name="target" type="number" min="1" required />
            </Field>
            <button className="primary" disabled={busy}>
              {t("save")}
            </button>
          </form>
        </Dialog>
      )}
      {editing && (
        <Dialog
          t={t}
          title={t(editing.id ? "edit" : "create")}
          onClose={() => setEditing(null)}
        >
          <form onSubmit={save}>
            <div className="form-grid">
              {c.fields.map((field) => (
                <Field
                  key={field}
                  label={
                    t(field) +
                    (["start_time", "expected_finish"].includes(field)
                      ? ` (${zone})`
                      : "")
                  }
                >
                  {relations[field] ? (
                    <select
                      name={field}
                      defaultValue={String(editing[field] || "")}
                      required={field === "product_id"}
                    >
                      <option value="">{t("unassigned")}</option>
                      {(s.tables[relatedTable(field)] || [])
                        .filter(
                          (x) =>
                            !x.archived &&
                            x.id !== editing.id &&
                            (field !== "operator_id" ||
                              x.status === "approved"),
                        )
                        .map((x) => (
                          <option key={String(x.id)} value={String(x.id)}>
                            {x.display_name
                              ? String(x.display_name)
                              : localName(x, lang)}
                          </option>
                        ))}
                    </select>
                  ) : field === "type" || field === "status" ? (
                    <select
                      name={field}
                      defaultValue={String(
                        editing[field] ||
                          (field === "type" ? "machine" : "planned"),
                      )}
                    >
                      {(field === "type"
                        ? [
                            "machine",
                            "manual_station",
                            "assembly_table",
                            "packing_station",
                            "inspection_station",
                            "production_cell",
                            "other",
                          ]
                        : ["planned", "active", "completed", "cancelled"]
                      ).map((x) => (
                        <option key={x} value={x}>
                          {t(x)}
                        </option>
                      ))}
                    </select>
                  ) : field === "requires_description" ? (
                    <input
                      name={field}
                      type="checkbox"
                      defaultChecked={Boolean(editing[field])}
                    />
                  ) : ["description", "notes"].includes(field) ? (
                    <textarea
                      name={field}
                      maxLength={2000}
                      defaultValue={String(editing[field] || "")}
                    />
                  ) : (
                    <input
                      name={field}
                      type={
                        numbers.includes(field)
                          ? "number"
                          : ["start_time", "expected_finish"].includes(field)
                            ? "datetime-local"
                            : "text"
                      }
                      min={
                        numbers.includes(field)
                          ? [
                              "position",
                              "produced_quantity",
                              "rejected_quantity",
                              "planned_capacity",
                            ].includes(field)
                            ? 0
                            : 0.001
                          : undefined
                      }
                      step="any"
                      maxLength={
                        ["start_time", "expected_finish"].includes(field)
                          ? 30
                          : 120
                      }
                      required={["name", "code", "target_quantity"].includes(
                        field,
                      )}
                      defaultValue={String(
                        (["start_time", "expected_finish"].includes(field) &&
                        editing[field]
                          ? formatLocalInput(String(editing[field]), zone)
                          : editing[field]) ??
                          ([
                            "produced_quantity",
                            "rejected_quantity",
                            "position",
                          ].includes(field)
                            ? 0
                            : ""),
                      )}
                    />
                  )}
                </Field>
              ))}
            </div>
            <button className="primary" disabled={busy}>
              {t("save")}
            </button>
          </form>
          {view === "centers" && editing.id && (
            <CenterCapabilities {...props} centerId={String(editing.id)} />
          )}
        </Dialog>
      )}
    </section>
  );
}
