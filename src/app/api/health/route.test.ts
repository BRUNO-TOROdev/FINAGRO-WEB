import { afterEach, describe, expect, it, vi } from "vitest";
import { GET } from "./route";

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
});

describe("GET /api/health", () => {
  it("fica saudável com env válido e Supabase acessível", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "https://project-ref.supabase.co");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "public-health-test-key");
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(new Response("[]", { status: 200 })));

    const response = await GET();
    const body = await response.json();

    expect(response.status).toBe(200);
    expect(body.status).toBe("ok");
    expect(body).not.toHaveProperty("url");
    expect(body).not.toHaveProperty("key");
    expect(JSON.stringify(body)).not.toContain("public-health-test-key");
  });

  it("diferencia configuração ausente de dependência indisponível", async () => {
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_URL", "");
    vi.stubEnv("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY", "public-health-test-key");

    const response = await GET();
    expect(response.status).toBe(500);
    expect((await response.json()).status).toBe("misconfigured");
  });
});
