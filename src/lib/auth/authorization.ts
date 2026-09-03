import type { OrganizationContext } from "@/types/database";

export class AuthenticationRequiredError extends Error {}
export class OrganizationAccessDeniedError extends Error {}
export class PermissionDeniedError extends Error {}

export interface AuthorizationRepository {
  findOrganizationContext(userId: string, slug: string): Promise<OrganizationContext | null>;
}

export async function authorizeOrganization(
  repository: AuthorizationRepository,
  userId: string | null,
  slug: string,
  permission?: string,
) {
  if (!userId) throw new AuthenticationRequiredError("AUTH_REQUIRED");
  const context = await repository.findOrganizationContext(userId, slug);
  if (!context?.is_active) throw new OrganizationAccessDeniedError("ORGANIZATION_ACCESS_DENIED");
  if (permission && !context.permissions.includes(permission)) {
    throw new PermissionDeniedError("PERMISSION_DENIED");
  }
  return context;
}
