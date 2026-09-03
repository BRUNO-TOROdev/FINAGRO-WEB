const MONEY = /^(?:R\$\s*)?(-?)(\d{1,3}(?:\.\d{3})*|\d+)(?:,(\d{1,2}))?$/;

export function moneyToDatabase(raw: string): string {
  const value = raw.trim();
  const match = value.match(MONEY);
  if (!match) throw new Error("INVALID_MONEY");
  const whole = match[2].replaceAll(".", "");
  const cents = (match[3] ?? "").padEnd(2, "0");
  const result = `${match[1]}${BigInt(whole)}.${cents}`;
  if (BigInt(`${match[1]}${whole}${cents}`) <= 0n) throw new Error("AMOUNT_MUST_BE_POSITIVE");
  return result;
}

export function formatBRL(raw: string): string {
  const match = raw.match(/^(-?)(\d+)(?:\.(\d{1,2}))?$/);
  if (!match) return raw;
  const whole = BigInt(match[2]).toLocaleString("pt-BR");
  return `${match[1] ? "-" : ""}R$ ${whole},${(match[3] ?? "").padEnd(2, "0")}`;
}

export const editableFinancialStatuses = ["PENDENTE", "AGENDADO"] as const;

export function positivePage(value: string | undefined) {
  if (!value || !/^\d+$/.test(value)) return 1;
  return Math.max(1, Number(value));
}
