import { PageHeading } from "@/components/layout/page-heading";
import { Notice } from "@/components/feedback/notice";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { requirePermission, requireUser } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { changeMembershipRole } from "@/features/memberships/actions";

type Member = { membership_id: string; user_id: string; email: string; display_name: string; role_id: string; role_name: string; is_active: boolean };

export default async function UsersPage({ params, searchParams }: { params: Promise<{ organizationSlug: string }>; searchParams: Promise<{ erro?: string; sucesso?: string }> }) {
  const { organizationSlug } = await params;
  const query = await searchParams;
  const [organization, user] = await Promise.all([requirePermission(organizationSlug, "users.manage"), requireUser()]);
  const supabase = await createClient();
  const [{ data: members }, { data: roles }] = await Promise.all([
    supabase.rpc("list_organization_members", { p_organization_id: organization.id }),
    supabase.from("roles").select("id,name").eq("organization_id", organization.id).order("name"),
  ]);
  return <><PageHeading eyebrow="Configurações" title="Usuários e perfis" description="Acesso por membership ativa e permissões mantidas no banco. Convites externos serão definidos em uma etapa própria."/><Notice {...query}/><Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="border-b bg-[#f7f9f7] text-xs uppercase tracking-wider text-[#6e7a72]"><tr><th className="px-5 py-4">Usuário</th><th className="px-5 py-4">Perfil</th><th className="px-5 py-4">Status</th><th className="px-5 py-4 text-right">Alterar perfil</th></tr></thead><tbody className="divide-y">{((members ?? []) as Member[]).map((member) => <tr key={member.membership_id}><td className="px-5 py-4"><p className="font-medium">{member.display_name}</p><p className="mt-1 text-xs text-[#78837b]">{member.email}</p></td><td className="px-5 py-4">{member.role_name}</td><td className="px-5 py-4"><Badge active={member.is_active}>{member.is_active ? "Ativo" : "Inativo"}</Badge></td><td className="px-5 py-4"><form action={changeMembershipRole.bind(null, organizationSlug, member.membership_id)} className="flex justify-end gap-2"><select name="roleId" defaultValue={member.role_id} disabled={member.user_id === user.id} className="h-10 rounded-lg border bg-white px-3 text-sm disabled:bg-[#f2f4f2]">{(roles ?? []).map((role) => <option key={role.id} value={role.id}>{role.name}</option>)}</select><Button variant="outline" disabled={member.user_id === user.id}>Salvar</Button></form></td></tr>)}</tbody></table></div></Card><p className="mt-4 text-xs text-[#78837b]">Por segurança, não é permitido alterar o próprio perfil. A criação e o convite de novos usuários dependem de uma decisão de onboarding e envio de e-mail ainda não definida.</p></>;
}
