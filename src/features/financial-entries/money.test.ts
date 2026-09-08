import { describe, expect, it } from "vitest";
import { centsToDatabaseMoney, databaseMoneyToCents, editableFinancialStatuses, formatBRL, moneyToDatabase, nonNegativeMoneyToDatabase, positivePage, splitMoneyEvenly } from "./money";

describe("money without floating point", () => {
  it("converts pt-BR values exactly", () => expect(moneyToDatabase("R$ 125.000,09")).toBe("125000.09"));
  it("rejects zero and negative values", () => { expect(() => moneyToDatabase("0,00")).toThrow(); expect(() => moneyToDatabase("-1,00")).toThrow(); });
  it("formats database decimals", () => expect(formatBRL("125000.09")).toBe("R$ 125.000,09"));
  it("never offers PAGO for manual editing", () => expect(editableFinancialStatuses).toEqual(["PENDENTE", "AGENDADO"]));
  it("normalizes pagination", () => { expect(positivePage(undefined)).toBe(1); expect(positivePage("0")).toBe(1); expect(positivePage("3")).toBe(3); });
  it("distributes installment cents deterministically", () => expect(splitMoneyEvenly("100,00",3)).toEqual(["33,34","33,33","33,33"]));
});

describe("optional financing components", () => {
  it("accepts omitted values as exact zero", () => expect(nonNegativeMoneyToDatabase("")).toBe("0.00"));
  it("preserves cents", () => expect(nonNegativeMoneyToDatabase("429.400,01")).toBe("429400.01"));
  it("rejects negative values", () => expect(() => nonNegativeMoneyToDatabase("-0,01")).toThrow("AMOUNT_MUST_NOT_BE_NEGATIVE"));
  it("treats integer NUMERIC values as reais", () => expect(centsToDatabaseMoney(databaseMoneyToCents(429400) + databaseMoneyToCents("72500.01"))).toBe("501900.01"));
});
