import { requestStatus, requestAttention } from './order-overview.mjs';
import { isScheduled } from './planning.mjs';

/** Display conditions only; persisted lifecycle and Planning remain authoritative. */
export function requestPresentation(request, items, now = Date.now()) {
  const status = requestStatus(items);
  const attention = requestAttention(items, now);
  const overdue = !['completed', 'cancelled'].includes(status) &&
    Date.parse(String(request.required_by || '')) < now;
  const scheduled = status === 'planned' && items.some(item => item.status === 'planned') &&
    items.filter(item => item.status === 'planned').every(isScheduled);
  const state = status === 'planned' ? scheduled ? 'scheduled' : 'waiting' : status;
  return { status, state, tone: overdue || attention ? 'delayed' : state, overdue, attention,
    label: status === 'planned' ? scheduled ? 'requestScheduled' : 'requestAwaitingPlanning'
      : status === 'active' && items.some(item => item.status === 'active') ? 'executionInProduction' : status };
}

export function requestStatusMatches(request, items, statuses = [], now = Date.now()) {
  if (!statuses.length || statuses.includes('all')) return true;
  const display = requestPresentation(request, items, now);
  return statuses.includes(display.status) ||
    (statuses.includes('delayed') && Boolean(display.overdue || display.attention));
}

/** Stored creator IDs, never job title or a fabricated Sales Owner relationship. */
export function requestCreators(requests) {
  const creators = new Map();
  for (const request of requests) {
    const id = request.requested_by ? String(request.requested_by) : 'unrecorded';
    if (!creators.has(id) || !creators.get(id)) creators.set(id, String(request.requested_by_name || ''));
  }
  return [...creators].map(([id, name]) => ({ id, name })).sort((a, b) => a.name.localeCompare(b.name));
}

/** Presentation filters over the entire retained snapshot, before rendering previews. */
export function requestQueueMatches(request, items, products, { search = '', product = '', line = '', creator = '' } = {}) {
  if (creator && (request.requested_by ? String(request.requested_by) : 'unrecorded') !== creator) return false;
  if (product && !items.some(item => String(item.product_id) === product)) return false;
  if (line && !items.some(item => String(item.line_id) === line)) return false;
  const words = search.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
  const text = [request.code, request.name, ...items.flatMap(item => {
    const found = products.find(product => product.id === item.product_id);
    return [found?.name, found?.name_ar, found?.code];
  })].join(' ').toLocaleLowerCase();
  return words.every(word => text.includes(word));
}
