import { useRef, useState } from "react";
import { Dialog, Field, localName } from "@/components/ui";
import { entryQuantities, productionProgress } from "@/utils/production-recording.mjs";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import ProductionHistory from './ProductionHistory';

export default function ProductionRecording({ snapshot: s, lang, t, can, command }: FeatureProps) {
  const units = s.tables.production_recording_units || [];
  const technicians = s.tables.production_technicians || [];
  const [unitKey, setUnitKey] = useState("");
  const [technician, setTechnician] = useState(String(technicians.find(x => x.user_id === s.user.id)?.id || ""));
  const shifts=s.tables.production_shifts || [];
  const activeShifts=shifts.filter(x=>!x.archived);
  const [shift,setShift]=useState('');
  const [correctionShift,setCorrectionShift]=useState('');
  const [good, setGood] = useState("");
  const [scrap, setScrap] = useState("0");
  const [note, setNote] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const [serverOverproduction, setServerOverproduction] = useState(false);
  const [busy, setBusy] = useState(false);
  const [notice, setNotice] = useState("");
  const [editing, setEditing] = useState<Row | null>(null);
  const [reason, setReason] = useState("");
  const request = useRef(crypto.randomUUID());
  const correctionRequest = useRef(crypto.randomUUID());
  const [correctionGood, setCorrectionGood] = useState("");
  const [correctionScrap, setCorrectionScrap] = useState("");
  const [correctionConfirmed, setCorrectionConfirmed] = useState(false);
  const [serverCorrectionOverproduction, setServerCorrectionOverproduction] = useState(false);
  const unit = units.find(x => `${x.unit_kind}:${x.unit_id}` === unitKey) || (!unitKey && units.length === 1 ? units[0] : undefined);
  const item = s.tables.production_orders?.find(x => x.id === unit?.item_id);
  const product = s.tables.products?.find(x => x.id === item?.product_id);
  const requestHeader = s.tables.production_requests?.find(x => x.id === item?.request_id);
  const progress = productionProgress(item, Number(good));
  const q = (n: number) => n.toLocaleString(lang);
  const unitLabel = (row: Row) => localName((row.unit_kind === "line" ? s.tables.production_lines : s.tables.work_centers)?.find(x => x.id === row.unit_id), lang);
  const quantityUnit = (row?: Row) => t(row?.unit === "meter" ? "meterShort" : row?.unit === "piece" ? "pieceShort" : "legacyUnit");
  const editable = can("orders", "edit");
  const validQuantities = Number.isFinite(Number(good)) && Number.isFinite(Number(scrap)) && Number(good)>=0 && Number(scrap)>=0 && Number(good)+Number(scrap)>0;
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!unit || !item || !validQuantities) return;
    setBusy(true);setNotice("");
    try {
      await command("record_production", { factory:s.factory?.id, unit_kind:unit.unit_kind, production_unit:unit.unit_id,
        item:item.id,technician,good:Number(good),scrap:Number(scrap),notes:note,confirm_overproduction:confirmed,request_id:request.current,shift:shift || null });
      request.current=crypto.randomUUID();setGood("");setScrap("0");setNote("");setConfirmed(false);setServerOverproduction(false);setNotice("saved");
    } catch (error) { const key=error instanceof Error ? error.message : "error";
      setNotice(key);if(key==="recordingOverproductionConfirm")setServerOverproduction(true); }
    finally { setBusy(false); }
  }
  function openCorrection(entry: Row) {
    const values=entryQuantities(entry);
    setEditing(entry);setCorrectionGood(String(values.good));setCorrectionScrap(String(values.scrap));
    setCorrectionShift(String(entry.shift_id || ''));
    setReason("");setCorrectionConfirmed(false);setServerCorrectionOverproduction(false);setNotice("");correctionRequest.current=crypto.randomUUID();
  }
  const correctedItem=(editing?.history_item as unknown as Row | undefined) || s.tables.production_orders?.find(x=>x.id===editing?.order_id);
  const correctionOverproduction=editing && productionProgress(correctedItem).good-entryQuantities(editing).good+Number(correctionGood)>Number(correctedItem?.target_quantity);
  return <section className="production-recording" aria-labelledby="production-recording-heading">
    <header><div><h3 id="production-recording-heading">{t("productionRecording")}</h3><p className="muted">{t("recordingHelp")}</p></div></header>
    {editable && <form onSubmit={submit} className="recording-form">
      <fieldset disabled={busy || !units.length}>
        <div className="form-grid">
          <Field label={t("recordingUnit")}><select required value={unit ? `${unit.unit_kind}:${unit.unit_id}` : ""}
            onChange={e=>{setUnitKey(e.target.value);setConfirmed(false);}}>
            <option value="">{t("recordingChooseUnit")}</option>
            {units.map(x=><option key={`${x.unit_kind}:${x.unit_id}`} value={`${x.unit_kind}:${x.unit_id}`}>
              {unitLabel(x)} · {t(x.unit_kind === "line" ? "line" : "independent")}</option>)}
          </select></Field>
          <Field label={t("recordingTechnician")}><select required value={technician} onChange={e=>setTechnician(e.target.value)}>
            <option value="">{t("recordingChooseTechnician")}</option>
            {technicians.map(x=><option key={String(x.id)} value={String(x.id)}>{String(x.display_name)}</option>)}
          </select></Field>
          {activeShifts.length>0 && <Field label={t('productionShift')}><select required value={shift} onChange={e=>setShift(e.target.value)}><option value="">{t('shiftChoose')}</option>{activeShifts.map(x=><option key={String(x.id)} value={String(x.id)}>{localName(x,lang)}</option>)}</select></Field>}
        </div>
        {!activeShifts.length && <p className="muted">{t(can('settings','edit')?'shiftSetup':'shiftNone')}</p>}
        {item && <div className="recording-current"><strong><bdi>{String(requestHeader?.code || item.code)}</bdi> · {localName(product,lang)}</strong>
          <dl className="recording-figures"><div><dt>{t("recordingRequired")}</dt><dd>{q(progress.required)} {quantityUnit(item)}</dd></div>
            <div><dt>{t("recordingGoodSoFar")}</dt><dd>{q(progress.good)} {quantityUnit(item)}</dd></div>
            <div><dt>{t("recordingRemaining")}</dt><dd>{q(progress.remaining)} {quantityUnit(item)}</dd></div></dl>
          {progress.remaining===0 && <p role="status">{t("recordingRequirementMet")}</p>}
        </div>}
        <div className="form-grid">
          <Field label={`${t("recordingGood")} (${quantityUnit(item)})`}><input required type="number" min="0" step="any" inputMode="decimal"
            value={good} onChange={e=>{setGood(e.target.value);setConfirmed(false);}} /></Field>
          <Field label={`${t("recordingScrap")} (${quantityUnit(item)})`}><input required type="number" min="0" step="any" inputMode="decimal"
            value={scrap} onChange={e=>setScrap(e.target.value)} /></Field>
        </div>
        <Field label={t("notes")}><input maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} /></Field>
        {item && good!=="" && <p className="recording-preview">{t("recordingAfterRemaining")}: <strong>{q(progress.afterRemaining)} {quantityUnit(item)}</strong></p>}
        {(progress.afterOverproduction>0 || serverOverproduction) && <label className="recording-confirm"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)} />
          {t("recordingOverproductionConfirm")}{progress.afterOverproduction>0 && <> · {q(progress.afterOverproduction)} {quantityUnit(item)}</>}</label>}
        <button className="primary" disabled={!item || !technician || (activeShifts.length>0 && !shift) || !validQuantities || ((progress.afterOverproduction>0 || serverOverproduction) && !confirmed)}>
          {t(busy ? "recordingSaving" : "recordingSubmit")}</button>
      </fieldset>
    </form>}
    {editable && !units.length && <p className="muted">{t("recordingNoActive")}</p>}
    {notice && <p role="status" className="notice">{t(notice)}</p>}
    <ProductionHistory snapshot={s} lang={lang} t={t} can={can} command={command} onCorrect={openCorrection}/>
    {editing && <Dialog title={t("recordingCorrect")} t={t} onClose={()=>{if(!busy)setEditing(null);}}>
      <form onSubmit={async e=>{e.preventDefault();setBusy(true);setNotice("");try {
        await command("correct_production_entry",{factory:s.factory?.id,entry:editing.id,good:Number(correctionGood),scrap:Number(correctionScrap),
          reason,confirm_overproduction:correctionConfirmed,request_id:correctionRequest.current,shift:correctionShift || null,change_shift:correctionShift!==String(editing.shift_id || '')});setEditing(null);setNotice("saved");
        } catch(error) {const key=error instanceof Error ? error.message : "error";setNotice(key);
          if(key==="recordingOverproductionConfirm")setServerCorrectionOverproduction(true);}finally{setBusy(false);}}}>
        <Field label={t("recordingGood")}><input required type="number" min="0" step="any" value={correctionGood} disabled={busy}
          onChange={e=>{setCorrectionGood(e.target.value);setCorrectionConfirmed(false);}} /></Field>
        <Field label={t("recordingScrap")}><input required type="number" min="0" step="any" value={correctionScrap} disabled={busy} onChange={e=>setCorrectionScrap(e.target.value)} /></Field>
        <Field label={t("reason")}><textarea required minLength={3} maxLength={2000} value={reason} disabled={busy} onChange={e=>setReason(e.target.value)} /></Field>
        <Field label={t('productionShift')}><select value={correctionShift} disabled={busy} onChange={e=>setCorrectionShift(e.target.value)}><option value="">{t('shiftNotRecorded')}</option>{shifts.filter(x=>!x.archived || x.id===editing.shift_id).map(x=><option key={String(x.id)} value={String(x.id)}>{localName(x,lang)}</option>)}</select></Field>
        {(correctionOverproduction || serverCorrectionOverproduction) && <label className="recording-confirm"><input type="checkbox" checked={correctionConfirmed} disabled={busy} onChange={e=>setCorrectionConfirmed(e.target.checked)} />{t("recordingOverproductionConfirm")}</label>}
        {notice && <p role="alert">{t(notice)}</p>}
        <button className="primary" disabled={busy || reason.trim().length<3 || Boolean((correctionOverproduction || serverCorrectionOverproduction) && !correctionConfirmed)}>{t("save")}</button>
      </form>
    </Dialog>}
  </section>;
}
