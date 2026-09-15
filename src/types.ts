export type Row = Record<string, string | number | boolean | null>;
export type Snapshot = {
  user: { id: string; email?: string };
  factory: Row | null;
  membership: Row | null;
  permissions: string[];
  tables: Record<string, Row[]>;
  fetchedAt: string;
  truncatedTables?: string[];
  supportFactories: Row[];
};
export type Language = "en" | "ar";
export type Translate = (key: string) => string;
