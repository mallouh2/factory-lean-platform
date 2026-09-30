/** Validate engineer-confirmed values without changing the loss estimate. */
export function validateActualScrap(totalText, shutdownText, restartText) {
  const entered = [totalText, shutdownText, restartText].map((value) => value !== "");
  const values = [totalText, shutdownText, restartText].map((value) =>
    value === "" ? null : Number(value));
  if (values.some((value) => value !== null && (!Number.isFinite(value) || value < 0)))
    return { error: "lossActualNonnegative" };
  let [total, shutdown, restart] = values;
  if (!entered[0] && entered[1] !== entered[2])
    return { error: "lossScrapNeedTotalOrBoth" };
  if (total === null && shutdown !== null && restart !== null)
    total = shutdown + restart;
  if (total !== null && (shutdown !== null || restart !== null)) {
    const parts = (shutdown || 0) + (restart || 0);
    const tolerance = Math.max(0.000001, Math.max(total, parts) * 0.000000001);
    if (parts > total + tolerance)
      return { error: "lossScrapBreakdownExceedsTotal" };
    if (shutdown !== null && restart !== null && Math.abs(total - parts) > tolerance)
      return { error: "lossScrapBreakdownMismatch" };
  }
  return { total, shutdown, restart, error: null };
}

export function hasDeferredWork(estimate, actual) {
  return Number(estimate?.deferred_quantity || 0) > 0 ||
    estimate?.estimated_recovery_minutes !== null &&
    estimate?.estimated_recovery_minutes !== undefined ||
    actual?.recovery_minutes !== null && actual?.recovery_minutes !== undefined;
}
