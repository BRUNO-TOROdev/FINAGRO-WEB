import { NextResponse } from "next/server";
import { getSupabaseEnv } from "@/lib/supabase/env";

export const dynamic = "force-dynamic";

export async function GET() {
  const checkedAt = new Date().toISOString();
  let supabase: ReturnType<typeof getSupabaseEnv>;

  try {
    supabase = getSupabaseEnv();
  } catch {
    return NextResponse.json(
      { status: "misconfigured", checkedAt },
      { status: 500, headers: { "Cache-Control": "no-store" } },
    );
  }

  try {
    const response = await fetch(`${supabase.url}/rest/v1/organizations?select=id&limit=1`, {
      cache: "no-store",
      headers: { apikey: supabase.key },
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
