import type { SupabaseClient } from "@supabase/supabase-js";
import type { AuthorizationRepository } from "./authorization";
import type { OrganizationContext } from "@/types/database";

export class SupabaseAuthorizationRepository implements AuthorizationRepository {
  constructor(private readonly supabase: SupabaseClient) {}

  async findOrganizationContext(userId: string, slug: string): Promise<OrganizationContext | null> {
    const { data: organization } = await this.supabase
      .from("organizations")
      .select("id,legal_name,trade_name,slug,is_active")
      .eq("slug", slug)
      .eq("is_active", true)
      .maybeSingle();
    if (!organization) return null;

    const { data: membership } = await this.supabase
      .from("memberships")
      .select("id,role_id,is_active,roles!inner(id,name)")
      .eq("organization_id", organization.id)
      .eq("user_id", userId)
      .eq("is_active", true)
      .maybeSingle();
    if (!membership) return null;

    const { data: grants } = await this.supabase
      .from("role_permissions")
      .select("permissions!inner(code)")
      .eq("organization_id", organization.id)
      .eq("role_id", membership.role_id);

    const role = membership.roles as unknown as { id: string; name: string };
    return {
      ...organization,
      membershipId: membership.id,
      roleId: role.id,
      roleName: role.name,
      permissions: (grants ?? []).map((grant) => (grant.permissions as unknown as { code: string }).code),
    } as OrganizationContext;
  }
}
