import Link from "next/link";
import { CirclePlus, Pencil, Power, PowerOff, Search } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Notice } from "@/components/feedback/notice";
import { PageHeading } from "@/components/layout/page-heading";
import { requireOrganizationMembership } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { applyChartTemplate, saveChartAccount, setChartAccountActive } from "@/features/chart-accounts/actions";
import type { ChartAccount } from "@/types/database";

function orderedTree(accounts: ChartAccount[]) {
  const children = new Map<string | null, ChartAccount[]>();
  accounts.forEach((account) => children.set(account.parent_id, [...(children.get(account.parent_id) ?? []), account]));
  children.forEach((items) => items.sort((a, b) => a.display_order - b.display_order || a.code.localeCompare(b.code, "pt-BR")));
  const result: ChartAccount[] = [];
  const visit = (parentId: string | null) => (children.get(parentId) ?? []).forEach((account) => { result.push(account); visit(account.id); });
  visit(null);
  return result;
}

export default async function ChartAccountsPage({ params, searchParams }: { params: Promise<{ organizationSlug: string }>; searchParams: Promise<{ q?: string; editar?: string; pai?: string; erro?: string; sucesso?: string }> }) {
  const { organizationSlug } = await params;
  const query = await searchParams;
  const organization = await requireOrganizationMembership(organizationSlug);
  const canManage = organization.permissions.includes("chart_accounts.manage");
  const supabase = await createClient();
  const [{ data }, { data: templates }] = await Promise.all([
    supabase.from("chart_accounts").select("id,organization_id,parent_id,code,name,level,managerial_type,nature,participates_dre,participates_cashflow,requires_farm,allows_allocation,requires_crop_season,display_order,is_active").eq("organization_id", organization.id),
    supabase.from("chart_account_templates").select("id,name,version").eq("is_active", true).order("name"),
  ]);
  const accounts = (data ?? []) as ChartAccount[];
  const editing = accounts.find((account) => account.id === query.editar);
  const term = query.q?.trim().toLocaleLowerCase("pt-BR");
  const visible = term ? accounts.filter((account) => account.code.toLocaleLowerCase().includes(term) || account.name.toLocaleLowerCase("pt-BR").includes(term)).sort((a,b) => a.code.localeCompare(b.code, "pt-BR")) : orderedTree(accounts);
  const parentDefault = editing?.parent_id ?? query.pai ?? "";
  return <><PageHeading eyebrow="Cadastros" title="Plano de Contas" description="Estrutura hierárquica própria da organização. Códigos e propriedades explícitas orientam as regras, nunca o nome da conta."/><Notice error={query.erro} success={query.sucesso}/>
    {canManage && <Card className="mb-6 p-6"><div className="flex flex-wrap items-start justify-between gap-4"><div><h2 className="text-lg font-semibold">{editing ? "Editar conta" : query.pai ? "Nova subconta" : "Nova conta"}</h2><p className="mt-1 text-sm text-[#667269]">A hierarquia é recalculada e validada pelo banco.</p></div>{editing && <Button asChild variant="outline"><Link href={`/app/${organizationSlug}/plano-de-contas`}>Cancelar</Link></Button>}</div><form action={saveChartAccount.bind(null, organizationSlug, editing?.id ?? null)} className="mt-5 space-y-4"><div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4"><label className="text-sm font-medium">Código<Input name="code" className="mt-2" defaultValue={editing?.code} required/></label><label className="text-sm font-medium lg:col-span-2">Nome<Input name="name" className="mt-2" defaultValue={editing?.name} required/></label><label className="text-sm font-medium">Ordem<Input name="displayOrder" type="number" min="0" className="mt-2" defaultValue={editing?.display_order ?? 0} required/></label><label className="text-sm font-medium">Conta pai<select name="parentId" defaultValue={parentDefault} className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm"><option value="">Sem conta pai</option>{orderedTree(accounts).filter((account) => account.id !== editing?.id).map((account) => <option key={account.id} value={account.id}>{"— ".repeat(Math.max(0, account.level - 1))}{account.code} {account.name}</option>)}</select></label><label className="text-sm font-medium">Tipo gerencial<select name="managerialType" defaultValue={editing?.managerial_type ?? "OUTRO"} className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm">{["RECEITA","CUSTO","DESPESA","INVESTIMENTO","FINANCIAMENTO","TRANSFERENCIA","SALDO_INICIAL","OUTRO"].map((value) => <option key={value}>{value}</option>)}</select></label><label className="text-sm font-medium">Natureza<select name="nature" defaultValue={editing?.nature ?? "NEUTRA"} className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm"><option>ENTRADA</option><option>SAIDA</option><option>NEUTRA</option></select></label></div><div className="flex flex-wrap gap-x-5 gap-y-3 text-sm">{[["participatesDre","Participa da DRE",editing?.participates_dre ?? true],["participatesCashflow","Participa do fluxo",editing?.participates_cashflow ?? true],["requiresFarm","Exige fazenda",editing?.requires_farm ?? false],["allowsAllocation","Permite rateio",editing?.allows_allocation ?? true],["requiresCropSeason","Exige safra",editing?.requires_crop_season ?? false]].map(([name,label,checked]) => <label key={String(name)} className="flex items-center gap-2"><input type="checkbox" name={String(name)} defaultChecked={Boolean(checked)}/>{String(label)}</label>)}</div><Button>Salvar conta</Button></form></Card>}
    <div className="mb-4 flex flex-col justify-between gap-3 sm:flex-row"><form className="flex max-w-md flex-1 gap-2"><div className="relative flex-1"><Search className="absolute left-3 top-3 size-4 text-[#78837b]"/><Input name="q" defaultValue={query.q} placeholder="Buscar por código ou nome" className="pl-9"/></div><Button variant="outline">Buscar</Button></form>{canManage && (templates ?? []).map((template) => <form key={template.id} action={applyChartTemplate.bind(null, organizationSlug, template.id)}><Button variant="outline">Aplicar {template.name} {template.version}</Button></form>)}</div>
    {(templates ?? []).length === 0 && canManage && accounts.length === 0 && <Card className="mb-4 border-dashed p-5"><p className="font-semibold">Template FINAGRO aguardando importação oficial</p><p className="mt-1 text-sm text-[#667269]">A infraestrutura está pronta, mas nenhuma conta foi inventada sem o catálogo homologado.</p></Card>}
    <Card className="overflow-hidden"><div className="divide-y">{visible.map((account) => <div key={account.id} className="flex items-center gap-3 px-4 py-3 hover:bg-[#fafcfa]"><div className="min-w-0 flex-1" style={{ paddingLeft: `${Math.min(account.level - 1, 8) * 20}px` }}><div className="flex flex-wrap items-center gap-2"><span className="font-mono text-sm font-semibold text-[#174d32]">{account.code}</span><span className="font-medium">{account.name}</span><Badge active={account.is_active}>{account.is_active ? "Ativa" : "Inativa"}</Badge></div><p className="mt-1 text-xs text-[#78837b]">Nível {account.level} · {account.managerial_type} · {account.nature}</p></div>{canManage && <div className="flex gap-1"><Button asChild variant="ghost" className="px-3" title="Criar subconta"><Link href={`?pai=${account.id}`}><CirclePlus className="size-4"/></Link></Button><Button asChild variant="ghost" className="px-3" title="Editar"><Link href={`?editar=${account.id}`}><Pencil className="size-4"/></Link></Button><form action={setChartAccountActive.bind(null, organizationSlug, account.id, !account.is_active)}><Button variant="ghost" className="px-3" title={account.is_active ? "Inativar" : "Reativar"}>{account.is_active ? <PowerOff className="size-4"/> : <Power className="size-4"/>}</Button></form></div>}</div>)}{visible.length === 0 && <p className="px-5 py-12 text-center text-sm text-[#667269]">{term ? "Nenhuma conta encontrada." : "Nenhuma conta cadastrada."}</p>}</div></Card>
  </>;
}
