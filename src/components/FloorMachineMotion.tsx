import { machineIconCategory } from "@/utils/machine-icons.mjs";
import type { Row } from "@/types";

type MotionState = "running" | "fault" | "planned" | "idle" | "blocked" | "home";

/** Presentation registry only: existing category icon keys retain their identity. */
export const MACHINE_VISUAL_TYPES = ["mixer", "extruder", "cooling", "printer", "cutter", "packing",
  "conveyor", "inspection", "manual", "cell", "cnc", "drill", "press", "injection", "generic",
  "heating", "pump", "assembly"] as const;
type MachineType = typeof MACHINE_VISUAL_TYPES[number];
const MACHINE_VISUALS = Object.fromEntries(MACHINE_VISUAL_TYPES.map(type => [type, () => silhouette(type)])) as Record<MachineType, () => React.ReactNode>;

export function machineVisualType(center: Row, categoryIconKey?: string | null): MachineType {
  const explicitType = String(center.type || "");
  const resolved = categoryIconKey ?? (MACHINE_VISUAL_TYPES.includes(explicitType as MachineType)
    ? explicitType : machineIconCategory(explicitType, String(center.name || "")));
  return MACHINE_VISUAL_TYPES.includes(resolved as MachineType) ? resolved as MachineType : "generic";
}

/** Lightweight generic machine functions; physical motion and assignment are independent. */
export default function MachineVisual({ type, state, borrowed = false }: {
  type: string;
  state: MotionState;
  borrowed?: boolean;
}) {
  const kind = MACHINE_VISUAL_TYPES.includes(type as MachineType) ? type as MachineType : "generic";
  return <span className={`ff2-machine-motion ff2-motion-${state}${borrowed ? " ff2-motion-borrowed" : ""}`} data-machine-kind={kind} data-motion-state={state} aria-hidden="true">
    <svg viewBox="0 0 160 88" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" focusable="false">
      <path className="ff2-motion-ground" d="M12 76H148" />
      {MACHINE_VISUALS[kind]()}
      {state === "blocked" && <g className="ff2-motion-gate"><path d="M137 40V67M131 40H143M131 67H143" /><path d="M133 47L141 55M133 55L141 63" /></g>}
    </svg>
  </span>;
}

function silhouette(kind: string) {
  switch (kind) {
    case "extruder": return <>
      <path className="ff2-motion-fill" d="M31 15H60L53 33H38Z" />
      <rect className="ff2-motion-fill" x="22" y="34" width="72" height="29" rx="8" />
      <path d="M31 63V75M81 63V75M94 42L107 47V54L94 59M22 44H13V54H22" />
      <path d="M107 50H145" strokeWidth="9" className="ff2-motion-material" />
      <path className="ff2-motion-extrusion" d="M109 50H145" strokeWidth="3" />
      <path d="M39 46H76M39 52H76" className="ff2-motion-detail" />
    </>;
    case "cooling": return <>
      <rect className="ff2-motion-fill" x="47" y="10" width="66" height="66" rx="14" />
      <circle cx="80" cy="43" r="25" /><circle cx="80" cy="43" r="4" />
      <g className="ff2-motion-fan">
        {[0, 90, 180, 270].map(angle => <path key={angle} transform={`rotate(${angle} 80 43)`} className="ff2-motion-fill" d="M79 39Q66 22 81 21Q91 25 84 39Z" />)}
      </g>
    </>;
    case "printer": return <>
      <path d="M27 75V21H96V30M36 30H86" />
      <g className="ff2-motion-print-head"><rect className="ff2-motion-fill" x="72" y="27" width="32" height="19" rx="5" /><path d="M82 46L88 53L94 46" /></g>
      <path d="M16 62H146" strokeWidth="11" className="ff2-motion-material" />
      <g className="ff2-motion-print-mark"><path d="M88 60V64M97 60V64M106 60V64M115 60V64" strokeWidth="3" /></g>
      <path d="M42 68V75M129 68V75" />
    </>;
    case "cutter": return <>
      <path d="M53 75V16H112V75M59 22H106" />
      <path d="M15 59H78" strokeWidth="10" className="ff2-motion-material" />
      <g className="ff2-motion-cut-piece"><path d="M88 59H143" strokeWidth="10" className="ff2-motion-material" /></g>
      <g className="ff2-motion-blade"><path className="ff2-motion-fill" d="M65 29H101V39L65 47Z" /><path d="M83 22V29" /></g>
      <path d="M31 65V75M131 65V75" />
    </>;
    case "packing": return <>
      <path d="M12 67H148M32 67V75M132 67V75" />
      <g className="ff2-motion-box"><path className="ff2-motion-fill" d="M47 37L80 24L113 37V61L80 72L47 61Z" /><path d="M47 37L80 49L113 37M80 49V72M64 31L96 43" /></g>
      <path className="ff2-motion-wrap" d="M39 44V23Q39 17 45 17H115Q121 17 121 23V44" />
    </>;
    case "mixer": return <>
      <rect className="ff2-motion-fill" x="47" y="17" width="66" height="53" rx="15" />
      <path d="M62 17V10H98V17M55 70V75M105 70V75" /><circle cx="80" cy="43" r="4" />
      <g className="ff2-motion-rotor"><path d="M80 24V62M61 43H99M67 30L93 56M67 56L93 30" /></g>
    </>;
    case "conveyor": return <>
      <rect className="ff2-motion-fill" x="16" y="44" width="128" height="21" rx="10" />
      <path d="M33 65V75M127 65V75" /><circle cx="28" cy="54" r="5" /><circle cx="132" cy="54" r="5" />
      <g className="ff2-motion-belt"><path d="M45 50L51 54L45 58M69 50L75 54L69 58M93 50L99 54L93 58" /></g>
      <rect className="ff2-motion-fill" x="61" y="26" width="32" height="18" rx="4" />
    </>;
    case "inspection": return <>
      <path d="M20 60H140M33 60V75M128 60V75" strokeWidth="3" />
      <rect className="ff2-motion-fill" x="43" y="47" width="75" height="12" rx="6" />
      <path d="M32 42V15H92" /><rect className="ff2-motion-fill" x="73" y="17" width="30" height="18" rx="5" />
      <path className="ff2-motion-scan" d="M78 42H101M78 47H101" /><path d="M130 19L135 24L144 14" />
    </>;
    case "manual": return <>
      <path d="M28 49H132M39 49V75M121 49V75" strokeWidth="4" />
      <rect className="ff2-motion-fill" x="67" y="39" width="29" height="10" rx="3" />
      <g className="ff2-motion-tool"><path d="M69 18L87 36M63 16L69 10L80 21L74 27M87 36L97 26" /></g>
      <path d="M50 56H110" />
    </>;
    case "cell": return <>
      <rect className="ff2-motion-fill" x="24" y="17" width="112" height="57" rx="10" /><path d="M33 64H127M43 74V76M119 74V76" />
      <g className="ff2-motion-arm"><path d="M56 59V48L75 30L103 40V52" strokeWidth="5" /><circle cx="75" cy="30" r="5" /><path d="M97 52H109" /></g>
    </>;
    case "cnc": return <>
      <rect className="ff2-motion-fill" x="24" y="14" width="112" height="61" rx="8" /><rect x="35" y="24" width="70" height="40" rx="4" />
      <path d="M114 27H124M114 36H124M48 58H94" />
      <g className="ff2-motion-cnc-head"><path d="M63 28H78V40H63ZM70 40V50" /></g>
    </>;
    case "drill": return <>
      <path d="M35 75H127M112 75V14H60" strokeWidth="4" /><path d="M44 57H103" />
      <g className="ff2-motion-drill-head"><rect className="ff2-motion-fill" x="52" y="16" width="25" height="20" rx="5" /><path d="M64 36V52M61 41L67 45M61 47L67 51" /></g>
      <path d="M53 58V75M99 58V75" />
    </>;
    case "press": return <>
      <path d="M34 75V14H126V75M34 70H126" strokeWidth="4" /><path d="M80 16V29" />
      <g className="ff2-motion-press"><rect className="ff2-motion-fill" x="47" y="29" width="66" height="12" rx="3" /></g>
      <path d="M48 60H112" strokeWidth="5" /><rect x="65" y="51" width="30" height="8" rx="3" />
    </>;
    case "injection": return <>
      <path d="M24 72H141M38 72V76M128 72V76M19 21H49L41 35H27" />
      <rect className="ff2-motion-fill" x="17" y="37" width="47" height="22" rx="6" /><path d="M64 47H81" strokeWidth="5" />
      <rect className="ff2-motion-fill" x="84" y="25" width="24" height="40" rx="4" />
      <g className="ff2-motion-mold"><rect className="ff2-motion-fill" x="112" y="25" width="24" height="40" rx="4" /></g>
    </>;
    case "heating": return <>
      <rect className="ff2-motion-fill" x="40" y="18" width="80" height="56" rx="10" />
      <path d="M51 62H109M54 74V76M106 74V76" />
      <g className="ff2-motion-heat"><path d="M62 54Q52 44 62 35T62 24M80 54Q70 44 80 35T80 24M98 54Q88 44 98 35T98 24" /></g>
    </>;
    case "pump": return <>
      <path d="M18 43H52M107 43H140V22M55 73H106" strokeWidth="6" />
      <circle className="ff2-motion-fill" cx="80" cy="43" r="28" /><circle cx="80" cy="43" r="5" />
      <g className="ff2-motion-rotor"><path d="M80 24Q95 25 92 38M99 43Q98 58 85 55M80 62Q65 61 68 48M61 43Q62 28 75 31" /></g>
    </>;
    case "assembly": return <>
      <path d="M27 68H133M41 68V75M119 68V75M80 16V29" />
      <g className="ff2-motion-join-left"><rect className="ff2-motion-fill" x="42" y="38" width="30" height="23" rx="4" /><path d="M72 49H78" /></g>
      <g className="ff2-motion-join-right"><rect className="ff2-motion-fill" x="88" y="38" width="30" height="23" rx="4" /><path d="M82 49H88" /></g>
      <path d="M75 27L80 32L85 27" />
    </>;
    default: return <>
      <rect className="ff2-motion-fill" x="32" y="23" width="96" height="45" rx="9" /><path d="M43 68V75M117 68V75M46 35H69" />
      <path className="ff2-motion-generic" d="M49 54H60L67 44L76 59L84 46H111" />
    </>;
  }
}
