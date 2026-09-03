import "server-only";
import { cache } from "react";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { authorizeOrganization, PermissionDeniedError } from "./authorization";
import { SupabaseAuthorizationRepository } from "./supabase-authorization-repository";

export const requireUser = cache(async () => {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) redirect("/login?erro=sessao-expirada");
  return data.user;
});

export const requireOrganizationMembership = cache(async (slug: string) => {
  const user = await requireUser();
  const supabase = await createClient();
  try {
    return await authorizeOrganization(new SupabaseAuthorizationRepository(supabase), user.id, slug);
  } catch {
    redirect("/sem-acesso");
  }
});

export async function requirePermission(slug: string, permission: string) {
  const context = await requireOrganizationMembership(slug);
  if (!context.permissions.includes(permission)) throw new PermissionDeniedError("PERMISSION_DENIED");
  return context;
}
