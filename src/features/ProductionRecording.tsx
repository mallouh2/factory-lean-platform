import { useEffect, useRef, useState } from "react";
import { Dialog, Field, localName } from "@/components/ui";
import { entryQuantities, productionProgress } from "@/utils/production-recording.mjs";
import type { Row } from "@/types";
import type { FeatureProps } from "./types";
import ProductionHistory from './ProductionHistory';
import { useUnfinished } from './useUnfinished';
import { unfinishedOutputValid } from '@/utils/unfinished-production.mjs';
import { shiftWindow } from '@/utils/production-shifts.mjs';

export default function ProductionRecording({ snapshot: s, lang, t, can, command  ,selectedLot }: FeatureProps & {selectedLot?:Row}) {
  const [inputSource,setInputSource]=useState(selectedLot?'unfinished':'normal');
  const [lotId,setLotId]=useState(String(selectedLot?.id || ''));
  const inventory=useUnfinished(s,false,1,inputSource==='unfinished'?String(selectedLot?.id || ''):'');
  const [processQuantity,setProcessQuantity]=useState('');
  const [unfinished,setUnfinished]=useState('0'),[remainingWork,setRemainingWork]=useState('');
  const [correctionUnfinished,setCorrectionUnfinished]=useState('0'),[correctionWork,setCorrectionWork]=useState('');
  const lots=!inventory.loaded && selectedLot && selectedLot.factory_id===s.factory?.id && !inventory.rows.some(x=>x.id===selectedLot.id)?[selectedLot,...inventory.rows]:inventory.rows;
  const lot=inputSource==='unfinished'?lots.find(x=>x.id===lotId):undefined;
  const units = inputSource==='unfinished' ? (lot?.destinations || []) as unknown as Row[] : s.tables.production_recording_units || [];
  const technicians = s.tables.production_technicians || [];
  const [unitKey, setUnitKey] = useState("");
  const [technician, setTechnician] = useState(String(technicians.find(x => x.user_id === s.user.id)?.id || ""));
  const shifts=s.tables.production_shifts || [];
  const activeShifts=shifts.filter(x=>!x.archived);
  const [shift,setShift]=useState('');
  const [manualShift,setManualShift]=useState(false),[overrideReason,setOverrideReason]=useState('');
  const shiftFactory=String(s.factory?.id || '');
  const [shiftPreview,setShiftPreview]=useState<{factory:string;context:Row | undefined}>({factory:shiftFactory,context:s.tables.production_shift_context?.[0]});
  const shiftContext=shiftPreview.factory===shiftFactory?shiftPreview.context:undefined;
  useEffect(()=>{
    const controller=new AbortController();
    fetch(`/api/data?${new URLSearchParams({factory:shiftFactory,shift_context:'1'})}`,{signal:controller.signal,cache:'no-store'})
      .then(async response=>{if(!response.ok)throw Error('dataWarning');return response.json();})
      .then(context=>setShiftPreview({factory:shiftFactory,context})).catch(error=>{if(error.name!=='AbortError')setShiftPreview({factory:shiftFactory,context:undefined});});
    return ()=>controller.abort();
  },[shiftFactory,s.fetchedAt]);
  const detectedShift=activeShifts.find(x=>x.id===shiftContext?.shift_id);
  const detectedWindow=shiftWindow(detectedShift);
  const needsManual=activeShifts.length>0 && !detectedShift;
  const shiftReady=manualShift ? Boolean(shift && overrideReason.trim().length>=3) : !needsManual;
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
  const validQuantities = unfinishedOutputValid(good,scrap,unfinished,remainingWork,inputSource==='normal'?null:processQuantity,Number(lot?.quantity_available ?? 0));
  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (!unit || !item || !validQuantities) return;
    setBusy(true);setNotice("");
    try {
      await command("record_production", { factory:s.factory?.id, unit_kind:unit.unit_kind, production_unit:unit.unit_id,
        item:item.id,technician,good:Number(good),scrap:Number(scrap),notes:note,confirm_overproduction:confirmed,request_id:request.current,
        shift:manualShift ? shift || null : null,shift_override_reason:manualShift ? overrideReason.trim() : null,unfinished:Number(unfinished),remaining_work:remainingWork.trim(),input_lot:lot?.id || null,input_quantity:lot?Number(processQuantity):0 });
      request.current=crypto.randomUUID();setGood("");setScrap("0");setUnfinished("0");setRemainingWork("");setProcessQuantity("");inventory.refresh();setNote("");setConfirmed(false);setServerOverproduction(false);setManualShift(false);setShift('');setOverrideReason('');setNotice("saved");
    } catch (error) { const key=error instanceof Error ? error.message : "error";
      setNotice(key);if(key==="recordingOverproductionConfirm")setServerOverproduction(true); }
    finally { setBusy(false); }
  }
  function openCorrection(entry: Row) {
    const values=entryQuantities(entry);
    setCorrectionUnfinished(String(entry.effective_unfinished || 0));setCorrectionWork(String(entry.effective_remaining_work || ''));
    setEditing(entry);setCorrectionGood(String(values.good));setCorrectionScrap(String(values.scrap));
    setCorrectionShift(String(entry.shift_id || ''));
    setReason("");setCorrectionConfirmed(false);setServerCorrectionOverproduction(false);setNotice("");correctionRequest.current=crypto.randomUUID();
  }
  const correctedItem=(editing?.history_item as unknown as Row | undefined) || s.tables.production_orders?.find(x=>x.id===editing?.order_id);
  const correctionOverproduction=editing && productionProgress(correctedItem).good-entryQuantities(editing).good+Number(correctionGood)>Number(correctedItem?.target_quantity);
  return <section className="production-recording" aria-labelledby="production-recording-heading">
    <header><div><h3 id="production-recording-heading">{t("productionRecording")}</h3><p className="muted">{t("recordingHelp")}</p></div></header>
    {editable && <form onSubmit={submit} className="recording-form">
      <fieldset disabled={busy}>
        <Field label={t("unfinishedInputSource")}><select value={inputSource} onChange={e=>{setInputSource(e.target.value);setUnitKey("");setLotId("");setProcessQuantity("");setConfirmed(false);}}><option value="normal">{t("unfinishedNormal")}</option><option value="unfinished">{t("unfinishedProduct")}</option></select></Field>
        {inputSource==='unfinished' && <div className="unfinished-input"><Field label={t("unfinishedProduct")}><select required value={lotId} onChange={e=>{setLotId(e.target.value);setUnitKey("");setProcessQuantity("");}}><option value="">{t("unfinishedChoose")}</option>{lots.map(x=><option key={String(x.id)} value={String(x.id)}>{String(x[lang==='ar'?'product_name_ar':'product_name'] || x.product_name)} · {String(x.request_code || x.item_code)} · {q(Number(x.quantity_available))} {quantityUnit(x)} · {String(x.remaining_work)}</option>)}</select></Field>
          {inventory.error && <p role="alert">{t(inventory.error)} <button type="button" onClick={inventory.refresh}>{t("refresh")}</button></p>}
          {lot && <><p>{t("unfinishedAvailable")}: <strong>{q(Number(lot.quantity_available))} {quantityUnit(lot)}</strong> · {String(lot.remaining_work)}</p><Field label={t("unfinishedProcess")}><input required type="number" min="0" max={Number(lot.quantity_available)} step="any" value={processQuantity} onChange={e=>setProcessQuantity(e.target.value)}/></Field><p className="muted">{t("unfinishedConservationHelp")}</p></>}
        </div>}
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
        </div>
        {activeShifts.length>0 && <div className="recording-shift" dir={lang==='ar'?'rtl':'ltr'}>
          <div><strong>{t('productionShift')}: {detectedShift?localName(detectedShift,lang):t(shiftContext?'shiftNoMatch':'loading')}</strong>
            {detectedWindow && <> · <bdi dir="ltr">{detectedWindow.start}–{detectedWindow.end}</bdi>{detectedWindow.overnight && <> · {t('shiftOvernight')}</>}</>}
            {detectedShift && <small> · {t('shiftAutoDetected')}</small>}
            {shiftContext && <small className="muted"> · <bdi>{String(shiftContext.timezone)}</bdi> <bdi dir="ltr">{String(shiftContext.local_time)}</bdi></small>}
          </div>
          <label className="recording-confirm"><input type="checkbox" checked={manualShift} onChange={e=>{setManualShift(e.target.checked);setShift('');setOverrideReason('');}}/>{t('shiftManualChoose')}</label>
          {manualShift && <div className="form-grid"><Field label={t('productionShift')}><select required value={shift} onChange={e=>setShift(e.target.value)}><option value="">{t('shiftChoose')}</option>{activeShifts.map(x=><option key={String(x.id)} value={String(x.id)}>{localName(x,lang)}</option>)}</select></Field>
            <Field label={t('shiftOverrideReason')}><input required minLength={3} maxLength={2000} value={overrideReason} onChange={e=>setOverrideReason(e.target.value)}/></Field></div>}
        </div>}
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
        <Field label={t('unfinishedQuantity')+' ('+quantityUnit(item)+')'}><input required type="number" min="0" step="any" value={unfinished} onChange={e=>setUnfinished(e.target.value)}/></Field>
        {Number(unfinished)>0 && <Field label={t('unfinishedRemainingWork')}><input required minLength={3} maxLength={2000} value={remainingWork} onChange={e=>setRemainingWork(e.target.value)}/></Field>}
        <Field label={t("notes")}><input maxLength={2000} value={note} onChange={e=>setNote(e.target.value)} /></Field>
        {item && good!=="" && <p className="recording-preview">{t("recordingAfterRemaining")}: <strong>{q(progress.afterRemaining)} {quantityUnit(item)}</strong></p>}
        {(progress.afterOverproduction>0 || serverOverproduction) && <label className="recording-confirm"><input type="checkbox" checked={confirmed} onChange={e=>setConfirmed(e.target.checked)} />
          {t("recordingOverproductionConfirm")}{progress.afterOverproduction>0 && <> · {q(progress.afterOverproduction)} {quantityUnit(item)}</>}</label>}
        <button className="primary" disabled={!item || !technician || !shiftReady || !validQuantities || ((progress.afterOverproduction>0 || serverOverproduction) && !confirmed)}>
          {t(busy ? "recordingSaving" : "recordingSubmit")}</button>
      </fieldset>
    </form>}
    {editable && !units.length && <p className="muted">{t(inputSource==='unfinished'?'unfinishedNoDestination':'recordingNoActive')}</p>}
    {notice && <p role="status" className="notice">{t(notice)}</p>}
    <ProductionHistory snapshot={s} lang={lang} t={t} can={can} command={command} onCorrect={openCorrection}/>
    {editing && <Dialog title={t("recordingCorrect")} t={t} onClose={()=>{if(!busy)setEditing(null);}}>
      <form onSubmit={async e=>{e.preventDefault();setBusy(true);setNotice("");try {
        await command("correct_production_entry",{factory:s.factory?.id,entry:editing.id,good:Number(correctionGood),scrap:Number(correctionScrap),
          reason,confirm_overproduction:correctionConfirmed,request_id:correctionRequest.current,unfinished:Number(correctionUnfinished),remaining_work:correctionWork.trim(),shift:correctionShift || null,change_shift:correctionShift!==String(editing.shift_id || '')});setEditing(null);setNotice("saved");
        } catch(error) {const key=error instanceof Error ? error.message : "error";setNotice(key);
          if(key==="recordingOverproductionConfirm")setServerCorrectionOverproduction(true);}finally{setBusy(false);}}}>
        <Field label={t("recordingGood")}><input required type="number" min="0" step="any" value={correctionGood} disabled={busy}
          onChange={e=>{setCorrectionGood(e.target.value);setCorrectionConfirmed(false);}} /></Field>
        <Field label={t("recordingScrap")}><input required type="number" min="0" step="any" value={correctionScrap} disabled={busy} onChange={e=>setCorrectionScrap(e.target.value)} /></Field>
        <Field label={t('unfinishedQuantity')}><input required type="number" min="0" step="any" value={correctionUnfinished} disabled={busy} onChange={e=>setCorrectionUnfinished(e.target.value)}/></Field>
        {Number(correctionUnfinished)>0 && <Field label={t('unfinishedRemainingWork')}><input required minLength={3} maxLength={2000} value={correctionWork} disabled={busy} onChange={e=>setCorrectionWork(e.target.value)}/></Field>}
        {editing.input_lot_id && <p>{t('unfinishedConservationHelp')} · {t('unfinishedProcess')}: {Number(editing.input_quantity)} {quantityUnit(editing)}</p>}
        <Field label={t("reason")}><textarea required minLength={3} maxLength={2000} value={reason} disabled={busy} onChange={e=>setReason(e.target.value)} /></Field>
        <Field label={t('productionShift')}><select value={correctionShift} disabled={busy} onChange={e=>setCorrectionShift(e.target.value)}><option value="">{t('shiftNotRecorded')}</option>{shifts.filter(x=>!x.archived || x.id===editing.shift_id).map(x=><option key={String(x.id)} value={String(x.id)}>{localName(x,lang)}</option>)}</select></Field>
        {(correctionOverproduction || serverCorrectionOverproduction) && <label className="recording-confirm"><input type="checkbox" checked={correctionConfirmed} disabled={busy} onChange={e=>setCorrectionConfirmed(e.target.checked)} />{t("recordingOverproductionConfirm")}</label>}
        {notice && <p role="alert">{t(notice)}</p>}
        <button className="primary" disabled={busy || reason.trim().length<3 || Boolean((correctionOverproduction || serverCorrectionOverproduction) && !correctionConfirmed)}>{t("save")}</button>
      </form>
    </Dialog>}
  </section>;
}
