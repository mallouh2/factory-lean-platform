import { useEffect, useState } from "react";
import { localName } from "@/components/ui";
import { sameCategory } from "@/utils/floor-visual.mjs";
import type { FeatureProps } from "./types";

export default function CenterAlternatives(props: FeatureProps & { centerId: string }) {
  const { snapshot, centerId, t, lang, can, command } = props;
  const centers = (snapshot.tables.work_centers || []).filter((c) => !c.archived);
  const center = centers.find((c) => String(c.id) === centerId);
  const saved = (snapshot.tables.work_center_alternatives || [])
    .filter((x) => String(x.work_center_id) === centerId)
    .map((x) => String(x.alternative_id));
  const [draft, setDraft] = useState<string[]>(saved);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  useEffect(() => { setDraft(saved); }, [centerId, saved.join(",")]);
  if (!center) return null;
  const candidates = centers.filter((c) => String(c.id) !== centerId && sameCategory(center, c));
  async function save() {
    setBusy(true);
    setNotice("");
    try {
      await command("configure_center_alternatives", {
        factory: snapshot.factory?.id, work_center: centerId, alternatives: draft,
      });
      setNotice("saved");
    } catch (error) {
      setNotice(error instanceof Error ? error.message : "error");
    } finally { setBusy(false); }
  }
  return <section className="center-alternatives">
    <h4>{t("alternativeMachines")}</h4>
    <p className="muted">{t("selectAlternatives")}</p>
    {candidates.map((c) => <label key={String(c.id)} className="ff2-check">
      <input type="checkbox" disabled={!can("centers", "edit") || busy}
        checked={draft.includes(String(c.id))}
        onChange={(e) => setDraft(e.target.checked ? [...draft, String(c.id)] : draft.filter((id) => id !== String(c.id)))} />
      {localName(c, lang)}
    </label>)}
    {!candidates.length && <p className="muted">{t("noSameCategoryMachines")}</p>}
    {can("centers", "edit") && <button className="primary" disabled={busy || draft.join(",") === saved.join(",")}
      onClick={() => void save()}>{t("save")}</button>}
    {notice && <p role="status">{t(notice)}</p>}
  </section>;
}
