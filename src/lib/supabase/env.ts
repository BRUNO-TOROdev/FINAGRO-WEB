import { z } from "zod";

type PublicEnvInput = {
  supabaseUrl?: string;
  supabasePublishableKey?: string;
  siteUrl?: string;
};

type PublicEnv = {
  supabaseUrl: string;
  supabasePublishableKey: string;
  siteUrl: string;
};

const urlSchema = z.url();

function missingPublicEnvError(names: string[]) {
  return new Error(`Variáveis públicas obrigatórias não configuradas: ${names.join(", ")}`);
}

function invalidPublicEnvError(names: string[]) {
  return new Error(`Variáveis públicas obrigatórias inválidas: ${names.join(", ")}`);
}

export function validatePublicEnv(input: PublicEnvInput): PublicEnv {
  const missing: string[] = [];

  if (!input.supabaseUrl?.trim()) missing.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!input.supabasePublishableKey?.trim()) missing.push("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  if (!input.siteUrl?.trim()) missing.push("NEXT_PUBLIC_SITE_URL");
  if (missing.length > 0) throw missingPublicEnvError(missing);

  const invalid: string[] = [];
  if (!urlSchema.safeParse(input.supabaseUrl).success) invalid.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!urlSchema.safeParse(input.siteUrl).success) invalid.push("NEXT_PUBLIC_SITE_URL");
  if (invalid.length > 0) throw invalidPublicEnvError(invalid);

  return {
    supabaseUrl: input.supabaseUrl!,
    supabasePublishableKey: input.supabasePublishableKey!,
    siteUrl: input.siteUrl!,
  };
}

export function getSupabaseEnv() {
  // Keep every NEXT_PUBLIC_* reference static so Next.js can inline it in
  // browser and Edge bundles. Do not replace these with a dynamic lookup.
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  const missing: string[] = [];

  if (!url?.trim()) missing.push("NEXT_PUBLIC_SUPABASE_URL");
  if (!key?.trim()) missing.push("NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY");
  if (missing.length > 0) throw missingPublicEnvError(missing);

  if (!urlSchema.safeParse(url).success) {
    throw invalidPublicEnvError(["NEXT_PUBLIC_SUPABASE_URL"]);
  }

  return { url: url!, key: key! };
}

export function getSiteUrl() {
  // This explicit reference is also required for Vercel/Edge inlining.
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL;
  if (!siteUrl?.trim()) throw missingPublicEnvError(["NEXT_PUBLIC_SITE_URL"]);
  if (!urlSchema.safeParse(siteUrl).success) {
    throw invalidPublicEnvError(["NEXT_PUBLIC_SITE_URL"]);
  }

  return new URL(siteUrl);
}
