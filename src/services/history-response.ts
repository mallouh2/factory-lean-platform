import { NextResponse } from "next/server";

/** History failures belong to their page, never to the global factory loader. */
export function historyError(error: unknown) {
  const code = error && typeof error === "object" && "code" in error ? error.code : null;
  const message = error instanceof Error ? error.message : "";
  const [status, key] = message === "unauthorized" ? [401, "unauthorized"]
    : code === "42501" || message === "permission_denied" ? [403, "permissionError"]
    : code === "22023" ? [400, "error"]
    : code === "P0002" ? [404, "noResults"] : [503, "dataWarning"];
  return NextResponse.json({ error: key }, { status: Number(status),
    headers: { "Cache-Control": "private, no-store" } });
}

export function historyPage(value: string | null) {
  if (value === null) return 1;
  const page = Number(value);
  if (!/^\d+$/.test(value) || !Number.isSafeInteger(page) || page < 1 || page > 1000000)
    throw { code: "22023" };
  return page;
}

export function historyUuid(value: string | null) {
  if (!value || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value))
    throw { code: "22023" };
  return value;
}
