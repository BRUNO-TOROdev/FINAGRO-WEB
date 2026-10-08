import Link from "next/link";
import { Pencil } from "lucide-react";
import { AllocationRuleForm } from "@/features/allocation-rules/allocation-rule-form";
import { formatPercentageTotal, percentageToMicros } from "@/features/allocation-rules/decimal";
import { saveAllocationRule } from "@/features/allocation-rules/actions";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Notice } from "@/components/feedback/notice";
import { PageHeading } from "@/components/layout/page-heading";
import { requireOrganizationMembership } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import type { AllocationRule, CropSeason, Farm } from "@/types/database";

type RuleItem = { allocation_rule_id: string; farm_id: string; percentage: string };

export default async function AllocationRulesPage({ params, searchParams }: { params: Promise<{ organizationSlug: string }>; searchParams: Promise<{ editar?: string; erro?: string; sucesso?: string }> }) {
  const { organizationSlug } = await params;
  const query = await searchParams;
  const organization = await requireOrganizationMembership(organizationSlug);
  const canManage = organization.permissions.includes("allocation_rules.manage");
  const supabase = await createClient();
  const [{ data: ruleData }, { data: itemData }, { data: farmData }, { data: seasonData }] = await Promise.all([
    supabase.from("allocation_rules").select("id,organization_id,crop_season_id,name,description,is_active,created_at,allocation_scope,effective_from,effective_to").eq("organization_id", organization.id).order("created_at", { ascending: false }),
    supabase.from("allocation_rule_items").select("allocation_rule_id,farm_id,percentage").eq("organization_id", organization.id),
    supabase.from("farms").select("id,organization_id,name,internal_code,total_area_ha,is_active").eq("organization_id", organization.id).order("name"),
    supabase.from("crop_seasons").select("id,organization_id,name,season_type,crop_name,starts_on,ends_on,is_closed,is_active").eq("organization_id", organization.id).order("starts_on", { ascending: false }),
  ]);
  const rules = (ruleData ?? []) as AllocationRule[];
  const items = (itemData ?? []) as RuleItem[];
  const farms = (farmData ?? []) as Farm[];
  const seasons = (seasonData ?? []) as CropSeason[];
  const editing = rules.find((rule) => rule.id === query.editar);
  const editingPercentages = Object.fromEntries(items.filter((item) => item.allocation_rule_id === editing?.id).map((item) => [item.farm_id, String(item.percentage).replace(".", ",")]));
  const farmNames = new Map(farms.map((farm) => [farm.id, farm.name]));
  const seasonNames = new Map<string | null, string>([[null, "Geral da organização"], ...seasons.map((season) => [season.id, season.name] as [string, string])]);
  return <><PageHeading eyebrow="Configurações" title="Regras de Rateio" description="Regras por Safra e regras Gerais da organização distribuem exatamente 100% entre fazendas quando ativas."/><Notice error={query.erro} success={query.sucesso}/>
    {canManage && <Card className="mb-6 p-6"><div className="flex items-start justify-between gap-4"><div><h2 className="text-lg font-semibold">{editing ? "Editar regra" : "Nova regra de rateio"}</h2><p className="mt-1 text-sm text-[#667269]">Salve como rascunho enquanto a distribuição não estiver completa.</p></div>{editing && <Button asChild variant="outline"><Link href={`/app/${organizationSlug}/rateios`}>Cancelar</Link></Button>}</div><AllocationRuleForm action={saveAllocationRule.bind(null, organizationSlug, editing?.id ?? null)} farms={farms.map(({ id, name, is_active }) => ({ id, name, is_active }))} seasons={seasons.map(({ id, name, is_active }) => ({ id, name, is_active }))} initial={editing ? { name: editing.name, cropSeasonId: editing.crop_season_id, description: editing.description ?? "", isActive: editing.is_active, percentages: editingPercentages } : undefined}/></Card>}
    <div className="grid gap-4 xl:grid-cols-2">{rules.map((rule) => { const ruleItems = items.filter((item) => item.allocation_rule_id === rule.id); const total = ruleItems.reduce((sum, item) => sum + percentageToMicros(String(item.percentage)), 0n); return <Card key={rule.id} className="p-5"><div className="flex items-start justify-between gap-4"><div><div className="flex flex-wrap items-center gap-2"><h2 className="font-semibold">{rule.name}</h2><Badge active={rule.is_active}>{rule.is_active ? "Ativa" : "Rascunho"}</Badge></div><p className="mt-1 text-sm text-[#667269]">{seasonNames.get(rule.crop_season_id) ?? "Safra não disponível"}</p></div>{canManage && <Button asChild variant="ghost" className="px-3"><Link href={`?editar=${rule.id}`} title="Editar"><Pencil className="size-4"/></Link></Button>}</div>{rule.description && <p className="mt-4 text-sm text-[#667269]">{rule.description}</p>}<div className="mt-5 divide-y rounded-lg border">{ruleItems.map((item) => <div key={item.farm_id} className="flex justify-between px-3 py-2.5 text-sm"><span>{farmNames.get(item.farm_id) ?? "Fazenda não disponível"}</span><span className="font-semibold">{String(item.percentage).replace(".", ",")}%</span></div>)}</div><div className="mt-3 flex justify-between text-sm font-semibold"><span>Total</span><span>{formatPercentageTotal(total)}%</span></div></Card>; })}{rules.length === 0 && <Card className="p-10 text-center text-sm text-[#667269] xl:col-span-2">Nenhuma regra de rateio cadastrada.</Card>}</div>
  </>;
}
