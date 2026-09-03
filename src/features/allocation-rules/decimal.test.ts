import { describe, expect, it } from "vitest";
import { formatPercentageTotal, ONE_HUNDRED_PERCENT, percentageToDatabase, percentageToMicros } from "./decimal";

describe("percentuais de rateio sem ponto flutuante", () => {
  it("soma 45 + 40 + 15 exatamente em 100%", () => {
    const total = ["45,00", "40,00", "15,00"].reduce((sum, value) => sum + percentageToMicros(value), 0n);
    expect(total).toBe(ONE_HUNDRED_PERCENT);
    expect(formatPercentageTotal(total)).toBe("100,00");
  });

  it("mantém 99,99 diferente de 100%", () => {
    expect(percentageToMicros("99,99")).not.toBe(ONE_HUNDRED_PERCENT);
  });

  it("normaliza seis casas decimais para PostgreSQL NUMERIC", () => {
    expect(percentageToDatabase("33,333334")).toBe("33.333334");
  });

  it("rejeita sinal, texto e precisão acima de seis casas", () => {
    expect(() => percentageToMicros("-1")).toThrow("INVALID_PERCENTAGE");
    expect(() => percentageToMicros("10.1234567")).toThrow("INVALID_PERCENTAGE");
    expect(() => percentageToMicros("dez")).toThrow("INVALID_PERCENTAGE");
  });
});
