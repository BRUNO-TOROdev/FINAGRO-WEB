import { describe, expect, it } from "vitest";
import { validatePublicEnv } from "./env";

const valid = {
  supabaseUrl: "https://project-ref.supabase.co",
  supabasePublishableKey: "public-test-key-that-must-never-appear-in-errors",
  siteUrl: "https://app.example.com",
};

describe("validatePublicEnv", () => {
  it("aceita as três variáveis públicas válidas", () => {
    expect(validatePublicEnv(valid)).toEqual(valid);
  });

  it.each([
    ["supabaseUrl", "NEXT_PUBLIC_SUPABASE_URL"],
    ["supabasePublishableKey", "NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY"],
    ["siteUrl", "NEXT_PUBLIC_SITE_URL"],
  ] as const)("identifica somente o nome ausente: %s", (field, expectedName) => {
    const input = { ...valid, [field]: undefined };

    expect(() => validatePublicEnv(input)).toThrow(expectedName);

    try {
      validatePublicEnv(input);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      expect(message).not.toContain(valid.supabaseUrl);
      expect(message).not.toContain(valid.supabasePublishableKey);
      expect(message).not.toContain(valid.siteUrl);
    }
  });
});
