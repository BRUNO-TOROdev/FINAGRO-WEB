export type FarmAreaInput = string | number | null | undefined;

export function parseOptionalFarmArea(value: FarmAreaInput): number | null {
  if (value === null || value === undefined || value === "") return null;

  if (typeof value === "string" && value.trim() === "") return null;

  const parsed = typeof value === "number"
    ? value
    : Number(value.trim().replace(",", "."));

  return Number.isFinite(parsed) ? parsed : null;
}

export function formatFarmArea(value: FarmAreaInput): string {
  const parsed = parseOptionalFarmArea(value);
  if (parsed === null) return "—";

  return `${new Intl.NumberFormat("pt-BR", {
    minimumFractionDigits: 0,
    maximumFractionDigits: 4,
  }).format(parsed)} ha`;
}

export function formatFarmAreaInput(value: FarmAreaInput): string {
  const parsed = parseOptionalFarmArea(value);
  return parsed === null ? "" : String(parsed).replace(".", ",");
}
