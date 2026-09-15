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
};
export const stringId = (row: Row | null | undefined) => String(row?.id || "");
