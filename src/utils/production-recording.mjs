/** Display/preview only: persisted database totals remain authoritative. */
export function productionProgress(item, entryGood = 0) {
  const required = Number(item?.target_quantity || 0);
  const good = Number(item?.good_quantity ?? (Number(item?.produced_quantity || 0) - Number(item?.rejected_quantity || 0)));
  const scrap = Number(item?.rejected_quantity || 0);
  const remaining = Number(item?.remaining_quantity ?? Math.max(required - good, 0));
  return { required, good, scrap, remaining, percent: required > 0 ? good * 100 / required : 0,
    overproduction: Number(item?.overproduction_quantity ?? Math.max(good-required,0)),
    afterRemaining: Math.max(required-good-Number(entryGood || 0),0),
    afterOverproduction: Math.max(good+Number(entryGood || 0)-required,0) };
}

export function entryQuantities(entry) {
  return { good: Number(entry.effective_good ?? (Number(entry.produced || 0)-Number(entry.rejected || 0))),
    scrap: Number(entry.effective_scrap ?? entry.rejected ?? 0) };
}
