const SCALE = 1_000_000n;
export const ONE_HUNDRED_PERCENT = 100n * SCALE;

export function percentageToMicros(input: string): bigint {
  const normalized = input.trim().replace(",", ".");
  if (!/^\d{1,3}(?:\.\d{0,6})?$/.test(normalized)) throw new Error("INVALID_PERCENTAGE");
  const [whole, fraction = ""] = normalized.split(".");
  return BigInt(whole) * SCALE + BigInt(fraction.padEnd(6, "0"));
}

export function percentageToDatabase(input: string): string {
  const micros = percentageToMicros(input);
  const whole = micros / SCALE;
  const fraction = (micros % SCALE).toString().padStart(6, "0");
  return `${whole}.${fraction}`;
}

export function formatPercentageTotal(micros: bigint): string {
  const whole = micros / SCALE;
  const cents = ((micros % SCALE) / 10_000n).toString().padStart(2, "0");
  return `${whole},${cents}`;
}
