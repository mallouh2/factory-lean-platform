import { useState } from "react";
import { Field, localName } from "@/components/ui";
import type { FeatureProps } from "./types";
export default function CenterCapabilities({
  centerId,
  ...props
}: FeatureProps & { centerId: string }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [busy, setBusy] = useState(false);
  const alternatives = (s.tables.work_center_alternatives || []).filter(
    (x) => x.work_center_id === centerId,
  );
  const capabilities = (s.tables.work_center_capabilities || []).filter(
    (x) => x.work_center_id === centerId,
  );
  return (
    <form
      onSubmit={async (e) => {
        e.preventDefault();
        setBusy(true);
        const f = new FormData(e.currentTarget);
        try {
          await command("configure_center_links", {
            factory: s.factory?.id,
            work_center: centerId,
            alternatives: f.getAll("alternative"),
            capabilities: (s.tables.products || [])
              .filter((p) => Number(f.get(String(p.id))) > 0)
              .map((p) => ({
                product_id: p.id,
                rate: Number(f.get(String(p.id))),
              })),
          });
        } catch {
        } finally {
          setBusy(false);
        }
      }}
    >
      <hr />
      <h3>{t("capabilities")}</h3>
      <p className="muted">{t("capabilitiesHelp")}</p>
      <div className="form-grid">
        {(s.tables.products || []).map((p) => (
          <Field key={String(p.id)} label={localName(p, lang)}>
            <input
              type="number"
              name={String(p.id)}
              min="0"
              step="any"
              defaultValue={String(
                capabilities.find((c) => c.product_id === p.id)?.rate || "",
              )}
            />
          </Field>
        ))}
      </div>
      <h3>{t("alternatives")}</h3>
      <div className="form-grid">
        {(s.tables.work_centers || [])
          .filter((c) => c.id !== centerId && !c.archived)
          .map((c) => (
            <label className="check" key={String(c.id)}>
              <input
                type="checkbox"
                name="alternative"
                value={String(c.id)}
                defaultChecked={alternatives.some(
                  (a) => a.alternative_id === c.id,
                )}
              />
              {localName(c, lang)}
            </label>
          ))}
      </div>
      <button className="primary" disabled={busy || !can("centers", "edit")}>
        {t("saveCapabilities")}
      </button>
    </form>
  );
}
