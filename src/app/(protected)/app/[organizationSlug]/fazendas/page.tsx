import Link from "next/link";
import { Pencil, Power } from "lucide-react";
import { PageHeading } from "@/components/layout/page-heading";
import { Notice } from "@/components/feedback/notice";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { requireOrganizationMembership } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { deactivateFarm, saveFarm } from "@/features/farms/actions";
import type { Farm } from "@/types/database";

export default async function FarmsPage({ params, searchParams }: { params: Promise<{ organizationSlug: string }>; searchParams: Promise<{ editar?: string; erro?: string; sucesso?: string }> }) {
  const { organizationSlug } = await params;
  const query = await searchParams;
  const organization = await requireOrganizationMembership(organizationSlug);
  const canManage = organization.permissions.includes("farms.manage");
  const supabase = await createClient();
  const { data } = await supabase.from("farms").select("id,organization_id,name,internal_code,total_area_ha,is_active").eq("organization_id", organization.id).order("name");
  const farms = (data ?? []) as Farm[];
  const editing = farms.find((farm) => farm.id === query.editar);
  const action = saveFarm.bind(null, organizationSlug, editing?.id ?? null);
  return <><PageHeading eyebrow="Cadastros" title="Fazendas" description="Unidades rurais vinculadas à organização. Registros com histórico são inativados, nunca excluídos."/><Notice error={query.erro} success={query.sucesso}/>{canManage && <Card className="mb-6 p-6"><h2 className="text-lg font-semibold">{editing ? "Editar fazenda" : "Nova fazenda"}</h2><form action={action} className="mt-5 grid gap-4 md:grid-cols-[2fr_1fr_1fr_auto]"><label className="text-sm font-medium">Nome<Input name="name" className="mt-2" defaultValue={editing?.name} required/></label><label className="text-sm font-medium">Código interno<Input name="internalCode" className="mt-2" defaultValue={editing?.internal_code ?? ""}/></label><label className="text-sm font-medium">Área total (ha)<Input name="totalAreaHa" className="mt-2" inputMode="decimal" defaultValue={editing?.total_area_ha ?? ""}/></label><div className="flex items-end gap-2"><Button type="submit">{editing ? "Salvar" : "Cadastrar"}</Button>{editing && <Button variant="outline" asChild><Link href={`/app/${organizationSlug}/fazendas`}>Cancelar</Link></Button>}</div></form></Card>}
  <Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="border-b bg-[#f7f9f7] text-xs uppercase tracking-wider text-[#6e7a72]"><tr><th className="px-5 py-4">Fazenda</th><th className="px-5 py-4">Código</th><th className="px-5 py-4">Área</th><th className="px-5 py-4">Status</th>{canManage && <th className="px-5 py-4 text-right">Ações</th>}</tr></thead><tbody className="divide-y">{farms.map((farm) => <tr key={farm.id} className="hover:bg-[#fafcfa]"><td className="px-5 py-4 font-medium">{farm.name}</td><td className="px-5 py-4 text-[#667269]">{farm.internal_code || "—"}</td><td className="px-5 py-4">{farm.total_area_ha ? `${farm.total_area_ha.replace(".", ",")} ha` : "—"}</td><td className="px-5 py-4"><Badge active={farm.is_active}>{farm.is_active ? "Ativa" : "Inativa"}</Badge></td>{canManage && <td className="px-5 py-4"><div className="flex justify-end gap-1"><Button asChild variant="ghost" className="px-3"><Link href={`?editar=${farm.id}`} title="Editar"><Pencil className="size-4"/></Link></Button>{farm.is_active && <form action={deactivateFarm.bind(null, organizationSlug, farm.id)}><Button variant="ghost" className="px-3" title="Inativar"><Power className="size-4"/></Button></form>}</div></td>}</tr>)}{farms.length === 0 && <tr><td colSpan={5} className="px-5 py-12 text-center text-[#667269]">Nenhuma fazenda cadastrada.</td></tr>}</tbody></table></div></Card></>;
}
