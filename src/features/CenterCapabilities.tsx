import { useState } from "react";
import { Field, localName } from "@/components/ui";
import type { FeatureProps } from "./types";

export default function CenterCapabilities({
  centerId,
  ...props
}: FeatureProps & { centerId: string }) {
  const { snapshot: s, t, lang, command, can } = props;
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const capabilities = (s.tables.work_center_capabilities || []).filter(
    (x) => x.work_center_id === centerId,
  );
  return (
      <form className="center-capabilities" onSubmit={async (e) => {
          e.preventDefault();
          const f = new FormData(e.currentTarget);
          const selected = (s.tables.products || []).filter((p) => Number(f.get(String(p.id))) > 0);
          if (selected.some((p) => !["meter", "piece"].includes(String(f.get(`${p.id}:unit`))))) {
            setError("planningRateUnitRequired");
            return;
          }
          if (selected.some((p) => !Number.isInteger(Number(f.get(`${p.id}:setup`))) ||
            Number(f.get(`${p.id}:setup`)) < 0 || Number(f.get(`${p.id}:setup`)) > 10080)) {
            setError("planningInvalidSetup");
            return;
          }
          if (capabilities.some((capability) =>
            !selected.some((product) => product.id === capability.product_id)) &&
            !confirm(t("confirmRemoveCapabilities"))) return;
          setError("");
          setBusy(true);
          try {
            await command("configure_center_capabilities", {
              factory: s.factory?.id,
              work_center: centerId,
              capabilities: selected
                .map((p) => ({
                  product_id: p.id,
                  rate: Number(f.get(String(p.id))),
                  rate_unit: f.get(`${p.id}:unit`),
                  setup_minutes: Number(f.get(`${p.id}:setup`)),
                })),
            });
          } catch (cause) {
            setError(cause instanceof Error ? cause.message : "error");
          } finally {
            setBusy(false);
          }
        }}
      >
        <h4>{t("capabilities")}</h4>
        <p className="muted">{t("capabilitiesHelp")}</p>
        {(s.tables.products || []).length ? (
          <div className="form-grid">
            {(s.tables.products || []).map((p) => (
              <div className="capability-rate-row" key={String(p.id)}>
                <Field label={localName(p, lang)}>
                  <input type="number" name={String(p.id)} min="0" step="any"
                    defaultValue={String(capabilities.find((c) => c.product_id === p.id)?.rate || "")} />
                </Field>
                <Field label={t("planningRateUnit")}>
                  <select name={`${p.id}:unit`} defaultValue={String(
                    capabilities.find((c) => c.product_id === p.id)?.rate_unit || "")}>
                    <option value="">{t("notSpecified")}</option>
                    <option value="meter">{t("meterShort")}</option>
                    <option value="piece">{t("pieceShort")}</option>
                  </select>
                </Field>
                <Field label={t("planningSetupMinutes")}>
                  <input type="number" name={`${p.id}:setup`} min="0" max="10080" step="1" required
                    defaultValue={String(capabilities.find((c) => c.product_id === p.id)?.setup_minutes || 0)} />
                </Field>
              </div>
            ))}
          </div>
        ) : (
          <p className="muted">{t("noProductsYet")}</p>
        )}
        {error && <p className="planning-warning" role="alert">{t(error)}</p>}
        <button
          className="primary"
          disabled={busy || !can("centers", "edit") || !(s.tables.products || []).length}
        >
          {t("saveCapabilities")}
        </button>
      </form>
  );
}
