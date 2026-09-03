"use server";

import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";

export async function changeMembershipRole(slug: string, membershipId: string, formData: FormData) {
  const roleId = String(formData.get("roleId") ?? "");
  try {
    const organization = await requirePermission(slug, "users.manage");
    const supabase = await createClient();
    const { error } = await supabase.rpc("change_membership_role", { p_organization_id: organization.id, p_membership_id: membershipId, p_role_id: roleId });
    if (error) throw error;
  } catch (error) {
    redirect(`/app/${slug}/usuarios?erro=${encodeURIComponent(userMessage(error))}`);
  }
  revalidatePath(`/app/${slug}/usuarios`);
  redirect(`/app/${slug}/usuarios?sucesso=Perfil atualizado.`);
}
