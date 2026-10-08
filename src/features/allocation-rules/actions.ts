"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";
import { percentageToDatabase } from "./decimal";
import { allocationRuleHeaderSchema } from "./schema";

export async function saveAllocationRule(slug: string, ruleId: string | null, formData: FormData) {
  const scope = formData.get("scope") === "GENERAL" ? "GENERAL" : "SEASONAL";
  const parsed = allocationRuleHeaderSchema.safeParse({ name: formData.get("name"), cropSeasonId: scope === "GENERAL" ? undefined : formData.get("cropSeasonId"), description: formData.get("description") });
  if (!parsed.success) redirect(`/app/${slug}/rateios?erro=${encodeURIComponent(parsed.error.issues[0].message)}`);
  try {
    const organization = await requirePermission(slug, "allocation_rules.manage");
    const items = [...formData.entries()].filter(([key, value]) => key.startsWith("percentage:") && String(value).trim() !== "").map(([key, value]) => ({
      farm_id: z.uuid().parse(key.slice("percentage:".length)),
      percentage: percentageToDatabase(String(value)),
    }));
    const supabase = await createClient();
    const request = scope === "GENERAL"
      ? supabase.rpc("save_general_allocation_rule", { p_organization_id: organization.id, p_rule_id: ruleId, p_name: parsed.data.name, p_description: parsed.data.description || null, p_is_active: formData.get("isActive") === "on", p_effective_from: formData.get("effectiveFrom"), p_effective_to: formData.get("effectiveTo") || null, p_items: items })
      : supabase.rpc("save_allocation_rule", { p_organization_id: organization.id, p_rule_id: ruleId, p_name: parsed.data.name, p_crop_season_id: parsed.data.cropSeasonId, p_description: parsed.data.description || null, p_is_active: formData.get("isActive") === "on", p_items: items });
    const { error } = await request;
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/rateios?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/rateios`);
  redirect(`/app/${slug}/rateios?sucesso=Regra de rateio salva com sucesso.`);
}
