import { NextRequest } from "next/server";
import { supabaseServer } from "./supabase";
export function verifyOrigin(request: NextRequest) {
  const origin = request.headers.get("origin");
  if (
    !origin ||
    origin !== new URL(process.env.APP_ORIGIN || request.url).origin
  )
    throw new Error("invalid_origin");
}
export async function authenticatedClient() {
  const db = await supabaseServer();
  const {
    data: { user },
    error,
  } = await db.auth.getUser();
  if (error || !user || !user.email_confirmed_at)
    throw new Error("unauthorized");
  return { db, user };
}
export async function authorize(
  factory: string,
  module: string,
  action: string,
  context?: Awaited<ReturnType<typeof authenticatedClient>>,
) {
  const { db, user } = context || await authenticatedClient();
  const { data, error } = await db.rpc("can_access", {
    factory,
    module,
    action,
  });
  if (error || data !== true) throw new Error("permission_denied");
  return { db, user };
}
export function safeError(error: unknown) {
  const message = error instanceof Error ? error.message : "";
  return {
    error:
      message === "unauthorized"
        ? "unauthorized"
        : message === "permission_denied"
          ? "permissionError"
          : "error",
  };
}
