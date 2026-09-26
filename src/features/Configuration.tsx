import CenterCapabilities from "./CenterCapabilities";
import CenterAlternatives from "./CenterAlternatives";
import {
  autoCode,
  formatLocalInput,
  localDateTimeToUtc,
} from "@/utils/manufacturing.mjs";
import { useState } from "react";
import {
  Dialog,
  Empty,
  Field,
  Badge,
  localName,
} from "@/components/ui";
import MachineIcon, {
  CATEGORY_ICON_KEYS,
} from "@/components/MachineIcon";
import type { FeatureProps } from "./types";
import type { Row } from "@/types";
const config: Record<string, {
  table: string;
  fields: string[];
  createFields?: string[];
}> = {
  factory: { table: "areas", fields: ["name", "name_ar"] },
  work_center_categories: {
    table: "work_center_categories",
    fields: ["name", "name_ar", "icon_key"],
  },
  lines: {
    table: "production_lines",
    fields: ["name", "name_ar", "area_id"],
  },
  centers: {
    table: "work_centers",
    fields: [
      "name",
      "name_ar",
      "category_id",
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
    // A new machine is master data only; operational values belong to later workflows.
    createFields: [
      "name",
      "name_ar",
      "category_id",
      "type",
      "area_id",
      "line_id",
      "description",
    ],
  },
  orders: {
    table: "production_orders",
    fields: [
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
      "stage",
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
  category_id: "work_center_categories",
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
type StandaloneEditor = {
  record: Row | null;
  onSaved: () => void;
  onCancel: () => void;
  blocked?: boolean;
};
function InlineEditor({ title, children }: {
  t: FeatureProps["t"];
  title: string;
  onClose: () => void;
  children: React.ReactNode;
}) {
  return <div className="management-record-form"><h3>{title}</h3>{children}</div>;
}
export default function Configuration({
  view,
  standalone,
  ...props
}: FeatureProps & { view: string; standalone?: StandaloneEditor }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [editing, setEditing] = useState<Row | null>(null),
    [search, setSearch] = useState(""),
    [busy, setBusy] = useState(false),
    [targetOrder, setTargetOrder] = useState<Row | null>(null);
  const activeEditing = standalone ? standalone.record || {} : editing;
  const EditorShell = standalone ? InlineEditor : Dialog;
  const c = config[view];
  const editorFields = activeEditing?.id ? c.fields.filter((field) =>
    !(standalone && view === "centers" && ["line_id", "position"].includes(field)),
  ) : c.createFields || c.fields;
  const permissionModule =
    view === "products" || view === "work_center_categories"
      ? view === "work_center_categories"
        ? "centers"
        : "orders"
      : view;
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
  const categories = s.tables.work_center_categories || [];
  const categoryIcon = (id: unknown) => {
    const cat = categories.find((k) => String(k.id) === String(id));
    return cat ? String(cat.icon_key) : "generic";
  };
  async function save(e: React.FormEvent<HTMLFormElement>) {
    e.preventDefault();
    setBusy(true);
    const creating = !activeEditing?.id;
    const activeFields = editorFields;
    const f = new FormData(e.currentTarget),
      payload: Record<string, unknown> = {};
    for (const field of activeFields) {
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
    if (creating && (view === "lines" || view === "centers"))
      payload.code = autoCode(view === "lines" ? "LINE" : "WC");
    try {
      await command("save_record", {
        factory: s.factory?.id,
        resource: view,
        id: activeEditing?.id || null,
        payload,
      });
      if (standalone) standalone.onSaved();
      else setEditing(null);
    } catch {
      // Keep the form open so the user can correct the input.
    } finally {
      setBusy(false);
    }
  }
  async function archive(row: Row) {
    if (!confirm(t("confirmArchive"))) return false;
    await command("save_record", {
        factory: s.factory?.id,
        resource: view,
        id: row.id,
        payload: { archived: true },
    });
    return true;
  }
  return (
    <section className={standalone ? "management-editor" : "panel"}>
      {!standalone && <>
      <header className="section-head">
        <input
          aria-label={t("search")}
          placeholder={t("search")}
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {view !== "orders" && can(permissionModule, "create") && (
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
                      <small className="cell-note">
                        {
                          categories.find(
                            (k) => String(k.id) === String(row.category_id),
                          )?.name
                        }
                      </small>
                    )}
                    {view === "work_center_categories" && (
                      <small className="cell-note">
                        <MachineIcon
                          center={row}
                          running={false}
                          categoryIconKey={String(row.icon_key || "generic")}
                        />
                      </small>
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
                      {["factory", "lines", "centers", "work_center_categories"].includes(view) &&
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
      </>}
      {activeEditing && (
        <EditorShell
          t={t}
          title={t(activeEditing.id ? "edit" : "create")}
          onClose={() => standalone ? standalone.onCancel() : setEditing(null)}
        >
          <form onSubmit={save}>
            <div className="form-grid">
              {editorFields.map(
                (field) => (
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
                    field === "category_id" ? (
                      <select
                        name={field}
                        defaultValue={String(activeEditing[field] || "")}
                        required
                      >
                        <option value="">{t("chooseCategory")}</option>
                        {(s.tables.work_center_categories || [])
                          .filter((x) => !x.archived)
                          .map((x) => (
                            <option key={String(x.id)} value={String(x.id)}>
                              {String(x.icon_key)} · {localName(x, lang)}
                            </option>
                          ))}
                      </select>
                    ) : (
                    <select
                      name={field}
                      defaultValue={String(activeEditing[field] || "")}
                      required={field === "product_id"}
                    >
                      <option value="">{t("unassigned")}</option>
                      {(s.tables[relatedTable(field)] || [])
                        .filter(
                          (x) =>
                            !x.archived &&
                            x.id !== activeEditing.id &&
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
                    )
                  ) : field === "icon_key" ? (
                    <select
                      name={field}
                      defaultValue={String(activeEditing[field] || "generic")}
                    >
                      {CATEGORY_ICON_KEYS.map((x) => (
                        <option key={x} value={x}>
                          {String(x)}
                        </option>
                      ))}
                    </select>
                  ) : field === "type" ||
                    field === "status" ||
                    field === "stage" ? (
                    <select
                      name={field}
                      defaultValue={String(
                        activeEditing[field] ||
                          (field === "type"
                            ? "machine"
                            : field === "stage"
                              ? "finished"
                              : "planned"),
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
                        : field === "stage"
                          ? ["raw", "wip", "semi_finished", "finished"]
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
                      defaultChecked={Boolean(activeEditing[field])}
                    />
                  ) : ["description", "notes"].includes(field) ? (
                    <textarea
                      name={field}
                      maxLength={2000}
                      defaultValue={String(activeEditing[field] || "")}
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
                        activeEditing[field]
                          ? formatLocalInput(String(activeEditing[field]), zone)
                          : activeEditing[field]) ??
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
            <button className="primary" disabled={busy || standalone?.blocked || !can(permissionModule, activeEditing.id ? "edit" : "create")}>
              {t("save")}
            </button>
          </form>
          {view === "centers" && activeEditing.id && (
            <>
              <CenterAlternatives {...props} centerId={String(activeEditing.id)} />
              <CenterCapabilities {...props} centerId={String(activeEditing.id)} />
            </>
          )}
          {standalone && activeEditing.id && can(permissionModule, "delete") && (
            <button className="management-archive" onClick={() => void archive(activeEditing).then((saved) => { if (saved) standalone.onSaved(); }).catch(() => {})}>{t("archive")}</button>
          )}
        </EditorShell>
      )}
    </section>
  );
}
