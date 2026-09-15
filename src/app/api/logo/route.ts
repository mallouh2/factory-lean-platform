import { NextRequest, NextResponse } from "next/server";
import { authorize, verifyOrigin, safeError } from "@/services/authorization";
export async function POST(req: NextRequest) {
  try {
    verifyOrigin(req);
    const form = await req.formData();
    const factory = String(form.get("factory"));
    const file = form.get("file");
    const { db } = await authorize(factory, "settings", "edit");
    if (
      !(file instanceof File) ||
      file.size > 2097152 ||
      !["image/png", "image/jpeg", "image/webp"].includes(file.type)
    )
      throw new Error("invalid_upload");
    const bytes = new Uint8Array(await file.arrayBuffer());
    const valid =
      (file.type === "image/png" &&
        bytes[0] === 137 &&
        bytes[1] === 80 &&
        bytes[2] === 78 &&
        bytes[3] === 71) ||
      (file.type === "image/jpeg" &&
        bytes[0] === 255 &&
        bytes[1] === 216 &&
        bytes[2] === 255) ||
      (file.type === "image/webp" &&
        new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
        new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP");
    if (!valid) throw new Error("invalid_upload");
    const path = `${factory}/${crypto.randomUUID()}`;
    const { error } = await db.storage
      .from("factory-logos")
      .upload(path, bytes, { contentType: file.type, upsert: false });
    if (error) throw error;
    return NextResponse.json({ path });
  } catch (e) {
    return NextResponse.json(safeError(e), { status: 400 });
  }
}
export async function GET(req: NextRequest) {
  try {
    const factory = req.nextUrl.searchParams.get("factory") || "";
    const { db } = await authorize(factory, "factory", "view");
    const { data } = await db
      .from("factories")
      .select("logo_path")
      .eq("id", factory)
      .single();
    if (!data?.logo_path) return new NextResponse(null, { status: 404 });
    const { data: file, error } = await db.storage
      .from("factory-logos")
      .download(data.logo_path);
    if (error || !file) throw error;
    return new NextResponse(file, {
      headers: {
        "Content-Type": file.type,
        "Cache-Control": "private, no-store",
      },
    });
  } catch {
    return new NextResponse(null, { status: 403 });
  }
}
