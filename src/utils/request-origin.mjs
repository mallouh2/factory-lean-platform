/** Origin is persisted server truth; NULL historical origins are never inferred. */
export function requestOriginLabel(type) {
  return type === 'SALES_PRODUCTION' ? 'customerDemand' : type === 'STOCK_REPLENISHMENT'
    ? 'stockReplenishment' : type === 'INTERNAL_PRODUCTION' ? 'internalProduction' : 'legacyRequest';
}
export function internalReasonValid(reason) {
  return typeof reason === 'string' && reason.trim().length > 0 && reason.trim().length <= 2000;
}
