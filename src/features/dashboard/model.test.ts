import { describe, expect, it } from "vitest";
import { comparisonMetric, hasCoverageGap, lineByCode } from "./model";

describe("dashboard presentation model", () => {
  it("selects KPIs only by stable report-line code", () => {
    const report = { months: [], coverage: {}, lines: [{ code: "DRE.CALC.RESULTADO", label: "renamed", line_type: "CALCULATED", values: {}, total: "10.00" }] };
    expect(lineByCode(report, "DRE.CALC.RESULTADO")?.total).toBe("10.00");
    expect(lineByCode(report, "renamed")).toBeUndefined();
  });
  it("keeps projected-zero variance unavailable", () => {
    const metric = comparisonMetric({ months: [], lines: [{ code: "X", label: "X", line_type: "CALCULATED", values: {}, total: { projected: "0", actual: "5", variance_amount: "5", variance_percent: null } }] }, "X");
    expect(metric?.variance_percent).toBeNull();
  });
  it("shows only technical coverage gaps", () => {
    expect(hasCoverageGap({ months: [], lines: [], coverage: { entries_unmapped: 1 } })).toBe(true);
    expect(hasCoverageGap({ months: [], lines: [], coverage: { entries_unmapped: 0 } })).toBe(false);
  });
});
