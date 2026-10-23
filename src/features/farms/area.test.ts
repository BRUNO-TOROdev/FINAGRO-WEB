import { describe, expect, it } from "vitest";
import { formatFarmArea, formatFarmAreaInput, parseOptionalFarmArea } from "./area";

describe("farm area normalization", () => {
  it("accepts a numeric value returned by Supabase", () => {
    expect(parseOptionalFarmArea(1234.56)).toBe(1234.56);
  });

  it("accepts a database decimal represented as string", () => {
    expect(parseOptionalFarmArea("1234.5600")).toBe(1234.56);
  });

  it("keeps null and empty values optional", () => {
    expect(parseOptionalFarmArea(null)).toBeNull();
    expect(parseOptionalFarmArea("")).toBeNull();
  });

  it("keeps zero distinct from null", () => {
    expect(parseOptionalFarmArea(0)).toBe(0);
    expect(formatFarmArea(0)).toBe("0 ha");
  });

  it("accepts a decimal comma from the form", () => {
    expect(parseOptionalFarmArea("1234,5678")).toBe(1234.5678);
  });

  it("formats a numeric database value in pt-BR without throwing", () => {
    expect(() => formatFarmArea(1234.56)).not.toThrow();
    expect(formatFarmArea(1234.56)).toBe("1.234,56 ha");
  });

  it("prepares numeric values safely for the edit form", () => {
    expect(formatFarmAreaInput(1234.56)).toBe("1234,56");
    expect(formatFarmAreaInput(null)).toBe("");
  });
});
