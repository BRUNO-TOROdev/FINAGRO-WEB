import { AppShell } from "@/components/layout/app-shell";
import { requireOrganizationMembership, requireUser } from "@/lib/auth/server";

export default async function OrganizationLayout({ children, params }: { children: React.ReactNode; params: Promise<{ organizationSlug: string }> }) {
  const { organizationSlug } = await params;
  const [organization, user] = await Promise.all([requireOrganizationMembership(organizationSlug), requireUser()]);
  return <AppShell organization={organization} userEmail={user.email ?? "Usuário autenticado"}>{children}</AppShell>;
}
