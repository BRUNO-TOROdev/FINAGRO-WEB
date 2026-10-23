"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";
import { parseOptionalFarmArea } from "./area";
import { farmSchema } from "./schema";

function parse(formData: FormData) {
  return farmSchema.safeParse({
    name: formData.get("name"), internalCode: formData.get("internalCode"), totalAreaHa: formData.get("totalAreaHa"),
  });
}

export async function saveFarm(slug: string, farmId: string | null, formData: FormData) {
  const parsed = parse(formData);
  if (!parsed.success) redirect(`/app/${slug}/fazendas?erro=${encodeURIComponent(parsed.error.issues[0].message)}`);
  try {
    const organization = await requirePermission(slug, "farms.manage");
    const supabase = await createClient();
    const record = {
      name: parsed.data.name,
      internal_code: parsed.data.internalCode || null,
      total_area_ha: parseOptionalFarmArea(parsed.data.totalAreaHa),
    };
    const query = farmId
      ? supabase.from("farms").update(record).eq("id", farmId).eq("organization_id", organization.id)
      : supabase.from("farms").insert({ ...record, organization_id: organization.id });
    const { error } = await query;
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/fazendas?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/fazendas`);
  redirect(`/app/${slug}/fazendas?sucesso=Fazenda salva com sucesso.`);
}

export async function deactivateFarm(slug: string, farmId: string) {
  try {
    const organization = await requirePermission(slug, "farms.manage");
    const supabase = await createClient();
    const { error } = await supabase.from("farms").update({ is_active: false }).eq("id", farmId).eq("organization_id", organization.id);
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/fazendas?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/fazendas`);
}
