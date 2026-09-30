import { useState } from "react";
import { localName } from "@/components/ui";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";

function ProductLossProfile(props: FeatureProps & {
  centerId: string; capability: Row;
}) {
  const { snapshot: s, t, lang, command, can, centerId, capability } = props;
  const product = (s.tables.products || []).find((x) => x.id === capability.product_id);
  const profile = (s.tables.production_loss_profiles || []).find((x) =>
    x.work_center_id === centerId && x.product_id === capability.product_id);
  const recovery = (s.tables.production_loss_recovery_rates || []).find((x) =>
    x.work_center_id === centerId && x.product_id === capability.product_id);
  const [canDefer, setCanDefer] = useState(profile?.can_defer === true ? "yes"
    : profile?.can_defer === false ? "no" : "unknown");
  const [scrapExpected, setScrapExpected] = useState(profile?.scrap_expected === true
    ? "yes" : profile?.scrap_expected === false ? "no" : "unknown");
  const [shutdown, setShutdown] = useState(String(profile?.shutdown_scrap_quantity ?? ""));
  const [restart, setRestart] = useState(String(profile?.restart_scrap_quantity ?? ""));
  const [scrapUnit, setScrapUnit] = useState(String(profile?.scrap_unit ?? ""));
  const [recoveryRate, setRecoveryRate] = useState(String(recovery?.rate ?? ""));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const editable = can("centers", "edit") && can("downtime", "edit");
  const unit = String(capability.rate_unit || "");
  async function saveProfile(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setError("");
    try {
      await command("configure_production_loss_profile", {
        factory: s.factory?.id, work_center: centerId, product: capability.product_id,
        can_defer: canDefer === "unknown" ? null : canDefer === "yes",
        scrap_expected: scrapExpected === "unknown" ? null : scrapExpected === "yes",
        shutdown_scrap: scrapExpected === "yes" ? Number(shutdown) : null,
        restart_scrap: scrapExpected === "yes" ? Number(restart) : null,
        scrap_unit: scrapExpected === "yes" ? scrapUnit.trim() : null,
      });
    } catch (cause) { setError(cause instanceof Error ? cause.message : "error"); }
    finally { setBusy(false); }
  }
  async function saveRecovery(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true); setError("");
    try {
      await command("configure_production_loss_recovery_rate", {
        factory: s.factory?.id, work_center: centerId, product: capability.product_id,
        rate: Number(recoveryRate), unit,
      });
    } catch (cause) { setError(cause instanceof Error ? cause.message : "error"); }
    finally { setBusy(false); }
  }
  return <section className="capability-rate-row" aria-label={localName(product, lang)}>
    <h5>{localName(product, lang)}</h5>
    <p>{t("lossCapacity")}: <strong>{String(capability.rate)} {unit === "meter"
      ? t("meterShort") : t("pieceShort")}/h</strong></p>
    <form onSubmit={(event) => void saveProfile(event)} className="form-grid">
      <label>{t("lossCanDefer")}
        <select value={canDefer} onChange={(event) => setCanDefer(event.target.value)}>
          <option value="unknown">{t("lossUnknown")}</option>
          <option value="no">{t("lossNo")}</option>
          <option value="yes">{t("lossYes")}</option>
        </select>
      </label>
      <label>{t("lossScrapExpected")}
        <select value={scrapExpected}
          onChange={(event) => setScrapExpected(event.target.value)}>
          <option value="unknown">{t("lossUnknown")}</option>
          <option value="no">{t("lossNo")}</option>
          <option value="yes">{t("lossYes")}</option>
        </select>
      </label>
      {scrapExpected === "yes" && <>
        <label>{t("lossShutdownScrap")}
          <input type="number" min="0" step="any" required value={shutdown}
            onChange={(event) => setShutdown(event.target.value)} />
        </label>
        <label>{t("lossRestartScrap")}
          <input type="number" min="0" step="any" required value={restart}
            onChange={(event) => setRestart(event.target.value)} />
        </label>
        <label>{t("lossScrapUnit")}
          <input required maxLength={30} value={scrapUnit}
            onChange={(event) => setScrapUnit(event.target.value)} />
        </label>
      </>}
      <button className="primary" disabled={busy || !editable}>{t("lossSaveAssumptions")}</button>
    </form>
    {canDefer === "yes" && <form onSubmit={(event) => void saveRecovery(event)}
      className="form-grid">
      <label>{t("lossRecoveryCapacity")} ({unit === "meter"
        ? t("meterShort") : t("pieceShort")}/h)
        <input type="number" min="0.001" step="any" required value={recoveryRate}
          onChange={(event) => setRecoveryRate(event.target.value)} />
      </label>
      <button disabled={busy || !editable}>{t("lossSaveRecovery")}</button>
    </form>}
    {error && <p className="planning-warning" role="alert">{t(error)}</p>}
  </section>;
}

export default function CenterLossProfile(props: FeatureProps & { centerId: string }) {
  const { snapshot: s, t, centerId } = props;
  const capabilities = (s.tables.work_center_capabilities || []).filter((x) =>
    x.work_center_id === centerId);
  return <section className="center-capabilities">
    <h4>{t("lossModel")}</h4>
    <p className="muted">{t("lossModelHelp")}</p>
    {capabilities.map((capability) => <ProductLossProfile
      key={String(capability.product_id)} {...props} capability={capability} />)}
  </section>;
}
