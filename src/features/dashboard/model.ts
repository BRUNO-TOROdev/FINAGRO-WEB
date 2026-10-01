export type Money = string | number;
export type ReportLine = { code: string; label: string; line_type: string; values: Record<string, Money>; total: Money | { actual: Money; projected: Money; variance_amount: Money; variance_percent: Money | null; warning?: string | null; aggregation?: string } };
export type Coverage = { entries_total?: number; entries_unmapped?: number; accounts_total?: number; accounts_mapped?: number; accounts_unmapped?: number; classified_amount?: Money; unclassified_amount?: Money; seasonal_config_missing?: unknown[] };
export type Report = { months: string[]; lines: ReportLine[]; coverage?: Coverage };
export type DashboardResult = { dre: Report; cash_flow: Report; comparison_dre: Report | null; comparison_cash_flow: Report | null };

export function lineByCode(report: Report | null | undefined, code: string) {
  return report?.lines.find((line) => line.code === code);
}

export function hasCoverageGap(report: Report | null | undefined) {
  const coverage = report?.coverage;
  return Boolean((coverage?.entries_unmapped ?? 0) > 0 || (coverage?.seasonal_config_missing?.length ?? 0) > 0);
}

export function comparisonMetric(report: Report | null | undefined, code: string) {
  const total = lineByCode(report, code)?.total;
  return total && typeof total === "object" ? total : null;
}

