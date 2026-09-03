"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";
import { chartAccountSchema } from "./schema";

export async function saveChartAccount(slug: string, accountId: string | null, formData: FormData) {
  const parsed = chartAccountSchema.safeParse({
    code: formData.get("code"), name: formData.get("name"), parentId: formData.get("parentId"),
    managerialType: formData.get("managerialType"), nature: formData.get("nature"), displayOrder: formData.get("displayOrder"),
  });
  if (!parsed.success) redirect(`/app/${slug}/plano-de-contas?erro=${encodeURIComponent(parsed.error.issues[0].message)}`);
  try {
    const organization = await requirePermission(slug, "chart_accounts.manage");
    const supabase = await createClient();
    const record = {
      code: parsed.data.code, name: parsed.data.name, parent_id: parsed.data.parentId || null,
      managerial_type: parsed.data.managerialType, nature: parsed.data.nature,
      display_order: parsed.data.displayOrder,
      participates_dre: formData.get("participatesDre") === "on",
      participates_cashflow: formData.get("participatesCashflow") === "on",
      requires_farm: formData.get("requiresFarm") === "on",
      allows_allocation: formData.get("allowsAllocation") === "on",
      requires_crop_season: formData.get("requiresCropSeason") === "on",
    };
    const query = accountId
      ? supabase.from("chart_accounts").update(record).eq("id", accountId).eq("organization_id", organization.id)
      : supabase.from("chart_accounts").insert({ ...record, organization_id: organization.id });
    const { error } = await query;
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/plano-de-contas?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/plano-de-contas`);
  redirect(`/app/${slug}/plano-de-contas?sucesso=Conta salva com sucesso.`);
}

export async function setChartAccountActive(slug: string, accountId: string, isActive: boolean) {
  try {
    const organization = await requirePermission(slug, "chart_accounts.manage");
    const supabase = await createClient();
    const { error } = await supabase.from("chart_accounts").update({ is_active: isActive }).eq("id", accountId).eq("organization_id", organization.id);
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/plano-de-contas?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/plano-de-contas`);
}

export async function applyChartTemplate(slug: string, templateId: string) {
  let message: string;
  try {
    const organization = await requirePermission(slug, "chart_accounts.manage");
    const supabase = await createClient();
    const { data, error } = await supabase.rpc("apply_chart_account_template", { p_organization_id: organization.id, p_template_id: templateId });
    if (error) throw error;
    message = data ? "Template aplicado com sucesso." : "Este template já foi aplicado nesta organização.";
    revalidatePath(`/app/${slug}/plano-de-contas`);
  } catch (error) {
    redirect(`/app/${slug}/plano-de-contas?erro=${encodeURIComponent(userMessage(error))}`);
  }
  redirect(`/app/${slug}/plano-de-contas?sucesso=${encodeURIComponent(message)}`);
}
