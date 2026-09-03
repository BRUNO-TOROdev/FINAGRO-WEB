import { describe, expect, it } from "vitest";
import { editableFinancialStatuses, formatBRL, moneyToDatabase, positivePage } from "./money";

describe("money without floating point", () => {
  it("converts pt-BR values exactly", () => expect(moneyToDatabase("R$ 125.000,09")).toBe("125000.09"));
  it("rejects zero and negative values", () => { expect(() => moneyToDatabase("0,00")).toThrow(); expect(() => moneyToDatabase("-1,00")).toThrow(); });
  it("formats database decimals", () => expect(formatBRL("125000.09")).toBe("R$ 125.000,09"));
  it("never offers PAGO for manual editing", () => expect(editableFinancialStatuses).toEqual(["PENDENTE", "AGENDADO"]));
  it("normalizes pagination", () => { expect(positivePage(undefined)).toBe(1); expect(positivePage("0")).toBe(1); expect(positivePage("3")).toBe(3); });
});
