import { machineIconCategory } from "@/utils/machine-icons.mjs";
import type { Row } from "@/types";

/**
 * Monochrome industrial icon set for Factory Floor V2. Consistent stroke
 * treatment, minimal detail; status accent and animation are applied by CSS
 * classes so color never lives here. Icon resolution priority: the work
 * center's CATEGORY icon (authoritative) → legacy type/name heuristic
 * (defensive fallback only) → generic.
 * Only a small internal part animates, and only while running. Rotating parts
 * (fan blades, mixer paddle) spin around the real 12,12 hub via
 * transform-box:view-box — never around their own bounding box.
 */
function shapes(category: string) {
  switch (category) {
    case "mixer":
      return (
        <>
          <rect x="5" y="10" width="14" height="10" rx="2.5" />
          <path d="M9 10V6.5A3 3 0 0 1 15 6.5V10" />
          <g className="ff2-part ff2-rotate">
            <circle cx="12" cy="15" r="2.6" />
            <path d="M12 12.4v5.2M9.8 13.7l4.4 2.6M14.2 13.7l-4.4 2.6" />
          </g>
        </>
      );
    case "extruder":
      return (
        <>
          <path d="M3 9h15a3 3 0 0 1 0 6H3z" />
          <path d="M18 12h3" />
          <g className="ff2-part">
            <path d="M5 10.5v3M8 10.5v3M11 10.5v3M14 10.5v3" />
          </g>
          <rect x="2" y="7" width="3" height="10" rx="1.2" />
        </>
      );
    case "cooling":
      return (
        <>
          <circle cx="12" cy="12" r="9" />
          <circle cx="12" cy="12" r="1.6" />
          {/* Four identical petals rotated 90° apart — perfect radial symmetry
              around the hub, so view-box rotation is visually smooth. */}
          <g className="ff2-part ff2-rotate">
            <path d="M12 10.2c-.4-1.9.4-4.3 2.3-5.2-.2 1.9-.8 3.7-2.3 5.2Z" />
            <path
              d="M12 10.2c-.4-1.9.4-4.3 2.3-5.2-.2 1.9-.8 3.7-2.3 5.2Z"
              transform="rotate(90 12 12)"
            />
            <path
              d="M12 10.2c-.4-1.9.4-4.3 2.3-5.2-.2 1.9-.8 3.7-2.3 5.2Z"
              transform="rotate(180 12 12)"
            />
            <path
              d="M12 10.2c-.4-1.9.4-4.3 2.3-5.2-.2 1.9-.8 3.7-2.3 5.2Z"
              transform="rotate(270 12 12)"
            />
          </g>
        </>
      );
    case "printer":
      return (
        <>
          <rect x="4" y="8" width="16" height="8" rx="2" />
          <path d="M7 16v3.5h10V16" />
          <rect x="8.5" y="4.5" width="7" height="3.5" rx="1" />
          <g className="ff2-part">
            <rect x="7.5" y="10.5" width="9" height="2.4" rx="1.2" />
          </g>
        </>
      );
    case "cutter":
      return (
        <>
          <path d="M4 19h16" />
          <path d="M6 19v-4h12v4" />
          <g className="ff2-part">
            <path d="M10 15V9.5L12 6l2 3.5V15z" />
          </g>
        </>
      );
    case "packing":
      return (
        <>
          <path d="M4.5 9.5 12 6l7.5 3.5v7L12 20l-7.5-3.5z" />
          <path d="M4.5 9.5 12 13l7.5-3.5M12 13v7" />
          <g className="ff2-part">
            <rect x="9.7" y="1.8" width="4.6" height="3.4" rx="0.8" />
          </g>
        </>
      );
    case "conveyor":
      return (
        <>
          <path d="M4.5 15.5h15" />
          <circle cx="5.5" cy="17.5" r="2" />
          <circle cx="18.5" cy="17.5" r="2" />
          <g className="ff2-part">
            <path d="M5 13.5h14" strokeDasharray="2.6 2.6" />
          </g>
          <rect x="8" y="6" width="8" height="6" rx="1.2" />
        </>
      );
    case "inspection":
      return (
        <>
          <circle cx="10.5" cy="10.5" r="6" />
          <path d="M15 15l5 5" />
          <path d="M8 10.5l2 2 2.8-3" />
        </>
      );
    case "manual":
      return (
        <>
          <path d="M4 17h16" />
          <path d="M6 17V9h12v8" />
          <path d="M9 9V6.5h6V9" />
        </>
      );
    case "cell":
      return (
        <>
          <rect x="4" y="4" width="7" height="7" rx="1.5" />
          <rect x="13" y="4" width="7" height="7" rx="1.5" />
          <rect x="8.5" y="13" width="7" height="7" rx="1.5" />
        </>
      );
    case "cnc":
      return (
        <>
          <path d="M4 20h16" />
          <path d="M5 20V6h14v14" />
          <path d="M9 6V3.5h6V6" />
          <g className="ff2-part">
            <path d="M12 9v4.5" />
            <path d="M10.4 15.8a1.8 1.8 0 1 0 3.2 0 1.8 1.8 0 1 0-3.2 0" />
          </g>
        </>
      );
    case "drill":
      return (
        <>
          <path d="M4 7h9v5H4z" />
          <path d="M13 9.5h3" />
          <g className="ff2-part">
            <path d="M16 8.5v3l3 1.5v-6z" />
            <path d="M19 7.5l2.5 1M19 9.5l2.5 1M19 11.5l2 1" />
          </g>
          <path d="M6 12v6M11 12v4" />
        </>
      );
    case "press":
      return (
        <>
          <path d="M4 20h16" />
          <path d="M5 4h14v4H5z" />
          <path d="M12 8v3" />
          <g className="ff2-part">
            <path d="M8.5 13.5h7l-1.5 3h-4z" />
          </g>
          <path d="M6 4v1M18 4v1" />
        </>
      );
    case "injection":
      return (
        <>
          <path d="M3 10h4v4H3z" />
          <path d="M7 10l4-4h6" />
          <path d="M7 14l4 4h6" />
          <g className="ff2-part">
            <path d="M17 6v8" />
            <circle cx="17" cy="16.5" r="1.6" />
          </g>
          <path d="M13 10h5" />
        </>
      );
    default:
      return (
        <>
          <circle cx="12" cy="12" r="8.2" />
          <g className="ff2-part">
            <circle cx="12" cy="12" r="3" />
          </g>
          <path d="M12 3.8v3M12 17.2v3M3.8 12h3M17.2 12h3M6.2 6.2l2.1 2.1M15.7 15.7l2.1 2.1M17.8 6.2l-2.1 2.1M8.3 15.7l-2.1 2.1" />
        </>
      );
  }
}

export const CATEGORY_ICON_KEYS = [
  "mixer",
  "extruder",
  "cooling",
  "printer",
  "cutter",
  "packing",
  "conveyor",
  "inspection",
  "manual",
  "cell",
  "cnc",
  "drill",
  "press",
  "injection",
  "generic",
] as const;

export default function MachineIcon({
  center,
  running,
  categoryIconKey,
}: {
  center: Row;
  running: boolean;
  /** Authoritative icon from the work center's category, when known. */
  categoryIconKey?: string;
}) {
  const category =
    categoryIconKey && categoryIconKey !== "generic"
      ? categoryIconKey
      : categoryIconKey === "generic"
        ? "generic"
        : machineIconCategory(
            String(center.type || ""),
            String(center.name || ""),
          );
  return (
    <svg
      viewBox="0 0 24 24"
      className={`ff2-icon ff2-icon-${category}${running ? " ff2-running" : ""}`}
      aria-hidden="true"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      {shapes(category)}
    </svg>
  );
}
