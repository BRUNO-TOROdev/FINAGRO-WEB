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
import { deactivateCropSeason, saveCropSeason } from "@/features/crop-seasons/actions";
import type { CropSeason } from "@/types/database";

const date = (value: string | null) => value ? value.split("-").reverse().join("/") : "—";

export default async function SeasonsPage({ params, searchParams }: { params: Promise<{ organizationSlug: string }>; searchParams: Promise<{ editar?: string; erro?: string; sucesso?: string }> }) {
  const { organizationSlug } = await params;
  const query = await searchParams;
  const organization = await requireOrganizationMembership(organizationSlug);
  const canManage = organization.permissions.includes("seasons.manage");
  const supabase = await createClient();
  const { data } = await supabase.from("crop_seasons").select("id,organization_id,name,season_type,crop_name,starts_on,ends_on,is_closed,is_active").eq("organization_id", organization.id).order("starts_on", { ascending: false });
  const seasons = (data ?? []) as CropSeason[];
  const editing = seasons.find((season) => season.id === query.editar);
  return <><PageHeading eyebrow="Cadastros" title="Safras" description="Ciclos agrícolas formais usados futuramente em orçamento, rateios e análises por safra."/><Notice error={query.erro} success={query.sucesso}/>{canManage && <Card className="mb-6 p-6"><h2 className="text-lg font-semibold">{editing ? "Editar safra" : "Nova safra"}</h2><form action={saveCropSeason.bind(null, organizationSlug, editing?.id ?? null)} className="mt-5 grid gap-4 md:grid-cols-3"><label className="text-sm font-medium">Nome<Input name="name" className="mt-2" defaultValue={editing?.name} required/></label><label className="text-sm font-medium">Tipo<select name="seasonType" defaultValue={editing?.season_type ?? "PRINCIPAL"} className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm"><option value="PRINCIPAL">Principal</option><option value="SAFRINHA">Safrinha</option><option value="OUTRA">Outra</option></select></label><label className="text-sm font-medium">Cultura<Input name="cropName" className="mt-2" defaultValue={editing?.crop_name ?? ""}/></label><label className="text-sm font-medium">Início<Input name="startsOn" type="date" className="mt-2" defaultValue={editing?.starts_on ?? ""}/></label><label className="text-sm font-medium">Fim<Input name="endsOn" type="date" className="mt-2" defaultValue={editing?.ends_on ?? ""}/></label><div className="flex items-end gap-2"><Button>{editing ? "Salvar" : "Cadastrar"}</Button>{editing && <Button asChild variant="outline"><Link href={`/app/${organizationSlug}/safras`}>Cancelar</Link></Button>}</div></form></Card>}
  <Card className="overflow-hidden"><div className="overflow-x-auto"><table className="w-full text-left text-sm"><thead className="border-b bg-[#f7f9f7] text-xs uppercase tracking-wider text-[#6e7a72]"><tr><th className="px-5 py-4">Safra</th><th className="px-5 py-4">Tipo / cultura</th><th className="px-5 py-4">Período</th><th className="px-5 py-4">Status</th>{canManage && <th className="px-5 py-4 text-right">Ações</th>}</tr></thead><tbody className="divide-y">{seasons.map((season) => <tr key={season.id}><td className="px-5 py-4 font-medium">{season.name}</td><td className="px-5 py-4 text-[#667269]">{season.season_type} · {season.crop_name || "Cultura não informada"}</td><td className="px-5 py-4">{date(season.starts_on)} — {date(season.ends_on)}</td><td className="px-5 py-4"><Badge active={season.is_active}>{season.is_active ? "Ativa" : "Inativa"}</Badge></td>{canManage && <td className="px-5 py-4"><div className="flex justify-end gap-1"><Button asChild variant="ghost" className="px-3"><Link href={`?editar=${season.id}`}><Pencil className="size-4"/></Link></Button>{season.is_active && <form action={deactivateCropSeason.bind(null, organizationSlug, season.id)}><Button variant="ghost" className="px-3"><Power className="size-4"/></Button></form>}</div></td>}</tr>)}{seasons.length === 0 && <tr><td colSpan={5} className="px-5 py-12 text-center text-[#667269]">Nenhuma safra cadastrada.</td></tr>}</tbody></table></div></Card></>;
}
