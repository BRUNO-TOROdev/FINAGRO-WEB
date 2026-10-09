import { describe, expect, it } from "vitest";
import { safeInternalPath } from "./redirects";

describe("safeInternalPath", () => {
  it("aceita somente caminhos internos absolutos", () => {
    expect(safeInternalPath("/app/finagro-demo")).toBe("/app/finagro-demo");
    expect(safeInternalPath("/redefinir-senha?origem=email")).toBe("/redefinir-senha?origem=email");
  });

  it("bloqueia redirects externos e caminhos ambíguos", () => {
    expect(safeInternalPath("//evil.example")).toBe("/app");
    expect(safeInternalPath("https://evil.example")).toBe("/app");
    expect(safeInternalPath("/\\evil.example")).toBe("/app");
    expect(safeInternalPath(null)).toBe("/app");
  });
});
