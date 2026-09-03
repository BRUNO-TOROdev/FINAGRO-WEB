"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";
import { cropSeasonSchema } from "./schema";

export async function saveCropSeason(slug: string, seasonId: string | null, formData: FormData) {
  const parsed = cropSeasonSchema.safeParse({ name: formData.get("name"), seasonType: formData.get("seasonType"), cropName: formData.get("cropName"), startsOn: formData.get("startsOn"), endsOn: formData.get("endsOn") });
  if (!parsed.success) redirect(`/app/${slug}/safras?erro=${encodeURIComponent(parsed.error.issues[0].message)}`);
  try {
    const organization = await requirePermission(slug, "seasons.manage");
    const supabase = await createClient();
    const record = { name: parsed.data.name, season_type: parsed.data.seasonType, crop_name: parsed.data.cropName || null, starts_on: parsed.data.startsOn || null, ends_on: parsed.data.endsOn || null };
    const query = seasonId
      ? supabase.from("crop_seasons").update(record).eq("id", seasonId).eq("organization_id", organization.id)
      : supabase.from("crop_seasons").insert({ ...record, organization_id: organization.id });
    const { error } = await query;
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/safras?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/safras`);
  redirect(`/app/${slug}/safras?sucesso=Safra salva com sucesso.`);
}

export async function deactivateCropSeason(slug: string, seasonId: string) {
  try {
    const organization = await requirePermission(slug, "seasons.manage");
    const supabase = await createClient();
    const { error } = await supabase.from("crop_seasons").update({ is_active: false }).eq("id", seasonId).eq("organization_id", organization.id);
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/safras?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/safras`);
}
