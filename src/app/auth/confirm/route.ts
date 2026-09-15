import { NextRequest, NextResponse } from "next/server";
import { supabaseServer } from "@/services/supabase";
export async function GET(req: NextRequest) {
  const db = await supabaseServer();
  const code = req.nextUrl.searchParams.get("code");
  const token_hash = req.nextUrl.searchParams.get("token_hash");
  let error: unknown = true;
  if (code) ({ error } = await db.auth.exchangeCodeForSession(code));
  else if (token_hash)
    ({ error } = await db.auth.verifyOtp({ token_hash, type: "email" }));
  return NextResponse.redirect(
    new URL(error ? "/?auth=error" : "/", process.env.APP_ORIGIN || req.url),
  );
}
