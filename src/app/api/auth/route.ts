import { NextRequest, NextResponse } from "next/server";
import { supabaseServer } from "@/services/supabase";
import { verifyOrigin, safeError } from "@/services/authorization";
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    const body = await req.json();
    const db = await supabaseServer();
    if (body.action === "signout") {
      await db.auth.signOut();
      return NextResponse.json({ ok: true });
    }
    let email = String(body.email || "").trim();
    const password = String(body.password || "");
    if (
      process.env.APP_ENV === "development" &&
      process.env.VERCEL_ENV !== "production" &&
      email === "ADMIN"
    )
      email = process.env.DEMO_EMAIL || "";
    if (
      !email.includes("@") ||
      email.length > 254 ||
      password.length < 8 ||
      password.length > 128
    )
      return NextResponse.json({ error: "authError" }, { status: 400 });
    if (body.action === "signup") {
      const { error } = await db.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: new URL(
            "/auth/confirm",
            process.env.APP_ORIGIN || req.url,
          ).href,
        },
      });
      return NextResponse.json(
        error ? { error: "authError" } : { verify: true },
        { status: error ? 400 : 200 },
      );
    }
    const { error } = await db.auth.signInWithPassword({ email, password });
    return NextResponse.json(error ? { error: "authError" } : { ok: true }, {
      status: error ? 401 : 200,
    });
  } catch (e) {
    return NextResponse.json(safeError(e), { status: 400 });
  }
}
