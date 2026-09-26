/** Presentation-only attention from existing planning times and order status. */
export function orderAttention(order, now = Date.now()) {
  if (!order || !["planned", "active"].includes(order.status)) return null;
  const finish = Date.parse(String(order.expected_finish || ""));
  if (Number.isFinite(finish) && finish < now) return "finishOverdue";
  const start = Date.parse(String(order.start_time || ""));
  if (order.status === "planned" && Number.isFinite(start) && start < now)
    return "startOverdue";
  return null;
}

export function orderMatchesFilter(order, filter, now = Date.now()) {
  if (filter === "all") return true;
  if (filter === "delayed") return Boolean(orderAttention(order, now));
  return order.status === filter;
}

/** Delays first, then active work, waiting work, and closed orders. */
export function sortOrdersForScan(orders, now = Date.now()) {
  const rank = (order) =>
    orderAttention(order, now) ? (order.status === "active" ? 0 : 1) :
    order.status === "active" ? 2 :
    order.status === "planned" ? 3 :
    order.status === "completed" ? 4 : 5;
  const timing = (order) => {
    const value = order.status === "planned" ? order.start_time : order.expected_finish;
    const time = Date.parse(String(value || ""));
    return Number.isFinite(time) ? time : Number.POSITIVE_INFINITY;
  };
  return [...orders].sort((a, b) =>
    rank(a) - rank(b) || timing(a) - timing(b) ||
    String(a.code || "").localeCompare(String(b.code || "")),
  );
}

/** Only a scheduled future start can be called next. */
export function nextScheduledOrder(orders, now = Date.now()) {
  return [...orders]
    .filter((order) => order.status === "planned" &&
      Number.isFinite(Date.parse(String(order.start_time || ""))) &&
      Date.parse(String(order.start_time)) >= now)
    .sort((a, b) => Date.parse(String(a.start_time)) - Date.parse(String(b.start_time)))[0];
}

/** Header state is derived from its product items; mixed units are never added. */
export function requestStatus(items) {
  if (!items.length) return "planned";
  if (items.every((item) => item.status === "completed")) return "completed";
  if (items.every((item) => item.status === "cancelled")) return "cancelled";
  if (items.some((item) => ["active", "completed"].includes(item.status))) return "active";
  return "planned";
}

export function requestAttention(items, now = Date.now()) {
  return items.map((item) => orderAttention(item, now)).find(Boolean) || null;
}

export function requestMatchesFilter(request, items, filter, now = Date.now()) {
  if (filter === "all") return true;
  if (filter === "delayed") return Boolean(requestAttention(items, now));
  return requestStatus(items) === filter;
}

export function sortRequestsForScan(requests, orders, now = Date.now()) {
  const byRequest = new Map();
  for (const item of orders) {
    const key = String(item.request_id);
    if (!byRequest.has(key)) byRequest.set(key, []);
    byRequest.get(key).push(item);
  }
  const rank = (request) => {
    const items = byRequest.get(String(request.id)) || [];
    if (requestAttention(items, now)) return 0;
    return { active: 1, planned: 2, completed: 3, cancelled: 4 }[requestStatus(items)] ?? 5;
  };
  const ranks = new Map(requests.map((request) => [request.id, rank(request)]));
  return [...requests].sort((a, b) => ranks.get(a.id) - ranks.get(b.id) ||
    String(b.created_at || "").localeCompare(String(a.created_at || "")));
}
