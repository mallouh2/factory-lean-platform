// Translate only explicit, known domain rejections; never expose raw SQL text.
export function recordingRejectionKey(reason,fallback){
 return ({SHIFT_EXPIRED:'prv3Expired',OVERPRODUCTION_CONFIRMATION_REQUIRED:'recordingOverproductionConfirm',
  output_compensation_required:'recordingCompensationRequired',output_compensation_exceeded:'recordingCompensationExceeded',
  output_compensation_stale:'recordingCompensationStale',output_quality_hold:'planningQualityHold'})[reason]||fallback;
}
