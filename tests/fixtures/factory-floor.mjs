// In-memory UI scenarios only. These never create or modify database rows.
export const floorScenarios = ["running", "stopped", "blocked", "idle", "borrowed", "alternative-stopped", "planned-stop", "unplanned-stop"];
export function floorSnapshot(scenario = "running") {
  const stamp = (minutes) => new Date(Date.now() + minutes * 60000).toISOString();
  const machine = (id, name, name_ar, position, extra = {}) => ({
    id, name, name_ar, position, line_id: "L1", status: "running", order_id: "O1",
    category_id: "CAT", dependency_mode: "blocking", impact_scope: "downstream", ...extra,
  });
  const centers = [machine("M1", "Material mixer", "خلاط المواد", 0),
    machine("M2", "Pipe extruder", "طارد الأنابيب", 1),
    machine("M3", "Cooling tank", "حوض التبريد", 2),
    machine("M4", "Cutting & packing", "القص والتغليف", 3),
    machine("A1", "Standby extruder", "الطارد الاحتياطي", 0,
      { line_id: "L2", status: "idle", order_id: null }),
    machine("A2", "Inspection station", "محطة الفحص", 1,
      { line_id: "L2", status: "idle", order_id: null, dependency_mode: "independent" })];
  const tables = { work_centers: centers,
    production_lines: [{ id: "L1", name: "LINE 1 — PVC Pipes", name_ar: "الخط ١ — أنابيب PVC" },
      { id: "L2", name: "LINE 2 — Standby", name_ar: "الخط ٢ — الاحتياطي" }],
    work_center_categories: [{ id: "CAT", name: "Extrusion", icon_key: "extruder" }],
    products: [{ id: "P1", name: "PVC Pipe 25 mm", name_ar: "أنبوب PVC مقاس ٢٥ مم" }],
    production_requests: [{ id: "R1", code: "PO-2026-041", name: "Local UI fixture" }],
    production_orders: [{ id: "O1", request_id: "R1", code: "ITEM-041-1", product_id: "P1",
      line_id: "L1", target_quantity: 5000, produced_quantity: 2300, unit: "meter", status: "active",
      start_time: stamp(-120), expected_finish: stamp(180), actual_start: stamp(-115) },
      { id: "O2", request_id: "R1", code: "ITEM-041-2", product_id: "P1", line_id: "L1",
        target_quantity: 3000, produced_quantity: 0, unit: "meter", status: "planned",
        start_time: stamp(180), expected_finish: stamp(360) }],
    downtime_events: [], production_transfers: [], production_entries: [],
    downtime_reasons: [{ id: "MECH", name: "Mechanical", name_ar: "ميكانيكي" }],
    work_center_alternatives: [{ work_center_id: "M2", alternative_id: "A1" }],
    memberships: [], work_center_capabilities: [{ work_center_id: "A1",
      product_id: "P1", rate: 100, rate_unit: "meter" }] };
  if (scenario === "idle") {
    centers.forEach((c) => { c.status = "idle"; c.order_id = null; });
    tables.production_orders = [];
  } else if (scenario !== "running") {
    centers[1].status = "stopped";
    if (scenario === "stopped") centers[1].impact_scope = "none";
    tables.downtime_events.push({ id: "STOP", work_center_id: "M2", line_id: "L1",
      started_at: stamp(-18), ended_at: null, reason_id: scenario === "planned-stop" ? null : "MECH",
      stop_nature: scenario === "planned-stop" ? "planned" : "unplanned",
      planned_activity: scenario === "planned-stop" ? "cleaning" : null });
    if (["borrowed", "alternative-stopped"].includes(scenario)) {
      centers[4].status = scenario === "borrowed" ? "running" : "stopped";
      centers[4].order_id = "O1";
      tables.production_transfers.push({ id: "TX", original_id: "M2", alternative_id: "A1",
        created_at: stamp(-12), ended_at: null });
      if (scenario === "alternative-stopped") tables.downtime_events.push({
        id: "ALTSTOP", work_center_id: "A1", started_at: stamp(-5), ended_at: null,
        reason_id: "MECH", stop_nature: "unplanned" });
    }
  }
  return { factory: { id: "LOCAL-FIXTURE", timezone: "Asia/Riyadh" },
    user: { id: "LOCAL-USER" }, membership: null,
    permissions: ["machine_status:edit", "orders:edit", "centers:view", "centers:edit"],
    tables, fetchedAt: new Date().toISOString(), supportFactories: [] };
}
