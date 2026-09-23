/**
 * Icon category for a work center. The explicit `type` value is the primary
 * mapping; bilingual name heuristics only disambiguate the generic "machine"
 * type, and the generic fallback always terminates the chain. Order matters:
 * an ambiguous name like "Printer Area Cooling" resolves to cooling, not printer.
 */
/** @type {[string, RegExp][]} */
const NAME_HINTS = [
  ["mixer", /mixer|خلاط/i],
  ["extruder", /extrud|بثق/i],
  ["cooling", /cool|تبريد/i],
  ["printer", /print|طباع/i],
  ["cutter", /cut|قطع/i],
  ["packing", /pack|تعبئ|تغليف/i],
  ["conveyor", /conveyor|puller|سحب|ناقل/i],
];
export function machineIconCategory(type, name = "") {
  const t = String(type || "").toLowerCase();
  if (t === "packing_station") return "packing";
  if (t === "inspection_station") return "inspection";
  if (t === "manual_station") return "manual";
  if (t === "assembly_table") return "manual";
  if (t === "production_cell") return "cell";
  if (t === "other") return "generic";
  const n = String(name || "");
  for (const [category, pattern] of NAME_HINTS)
    if (pattern.test(n)) return category;
  return "generic";
}
