import type { Snapshot, Translate, Language, Row } from "@/types";
export type Command = (
  command: string,
  args: Record<string, unknown>,
) => Promise<unknown>;
export type FeatureProps = {
  snapshot: Snapshot;
  t: Translate;
  lang: Language;
  command: Command;
  can: (module: string, action?: string) => boolean;
  onLanguageChange?: () => void;
  refreshSnapshot?: () => Promise<void | boolean>;
  onProductionHistoryOpen?: (mode?:'production'|'quality') => void;
  onOutputRelated?: (destination:OutputDestination) => void;
};
export type OutputDestination={factory:string;view:'production'|'quality'|'warehouse'|'planning'|'order';entry?:string;output?:string;work?:string;item?:string};
export const stringId = (row: Row | null | undefined) => String(row?.id || "");
