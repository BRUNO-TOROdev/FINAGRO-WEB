import { NextResponse } from "next/server";
import { getSupabaseEnv } from "@/lib/supabase/env";

export const dynamic = "force-dynamic";

export async function GET() {
  const checkedAt = new Date().toISOString();

  try {
    const { url, key } = getSupabaseEnv();
    const response = await fetch(`${url}/rest/v1/organizations?select=id&limit=1`, {
      cache: "no-store",
      headers: { apikey: key },
      signal: AbortSignal.timeout(3_000),
    });

    if (!response.ok) throw new Error("DEPENDENCY_UNAVAILABLE");

    return NextResponse.json(
      { status: "ok", checkedAt },
      { headers: { "Cache-Control": "no-store" } },
    );
  } catch {
    return NextResponse.json(
      { status: "unavailable", checkedAt },
      { status: 503, headers: { "Cache-Control": "no-store" } },
    );
  }
}
