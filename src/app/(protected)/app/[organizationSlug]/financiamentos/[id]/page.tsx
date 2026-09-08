import Link from "next/link";
import { notFound } from "next/navigation";
import { PageHeading } from "@/components/layout/page-heading";
import { Notice } from "@/components/feedback/notice";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { requireOrganizationMembership } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { centsToDatabaseMoney, databaseMoneyToCents, formatBRL } from "@/features/financial-entries/money";
import type { FinancingSummary } from "@/types/database";

const date = (value: string | null) => value ? new Intl.DateTimeFormat("pt-BR", { timeZone: "UTC" }).format(new Date(`${value}T00:00:00Z`)) : "—";
const total = (...values: (string | number)[]) => centsToDatabaseMoney(values.reduce<bigint>((sum, value) => sum + databaseMoneyToCents(value), 0n));

export default async function Page({ params, searchParams }: { params: Promise<{ organizationSlug: string; id: string }>; searchParams: Promise<{ sucesso?: string }> }) {
  const { organizationSlug, id } = await params;
  const query = await searchParams;
  const organization = await requireOrganizationMembership(organizationSlug);
  const supabase = await createClient();
  const [{ data: summary }, { data: contract }, { data: installments }] = await Promise.all([
    supabase.from("v_financing_contract_summary").select("*").eq("organization_id", organization.id).eq("id", id).maybeSingle(),
    supabase.from("financing_contracts").select("credit_entry_id,farm_id,allocation_rule_id,notes").eq("organization_id", organization.id).eq("id", id).maybeSingle(),
    supabase.from("financing_installments").select("id,installment_number,due_date,principal_amount,interest_amount,other_charges_amount,principal_entry_id,interest_entry_id").eq("organization_id", organization.id).eq("financing_contract_id", id).order("installment_number"),
  ]);
  if (!summary || !contract) notFound();
  const financing = summary as FinancingSummary;
  return <>
    <PageHeading eyebrow="Financiamento" title={`${financing.creditor_name} · ${financing.contract_number}`} description="O saldo devedor considera exclusivamente o principal efetivamente liquidado." />
    <Notice success={query.sucesso} />
    <div className="grid gap-4 md:grid-cols-4">
      {[["Principal contratado", financing.contracted_amount], ["Recebido", financing.received_amount], ["Principal pago", financing.principal_paid], ["Saldo devedor", financing.principal_balance], ["Juros previstos", financing.scheduled_interest], ["Encargos previstos", financing.scheduled_charges]].map(([label, value]) => <Card key={label} className="p-4"><p className="text-xs text-[#667269]">{label}</p><p className="mt-1 text-lg font-semibold">{formatBRL(String(value))}</p></Card>)}
    </div>
    <Card className="mt-5 overflow-hidden">
      <div className="flex items-center justify-between border-b p-5"><div><h2 className="font-semibold">Cronograma contratual</h2><p className="text-sm text-[#667269]">{financing.amortization_type.replace("_", " ")} · próxima parcela {date(financing.next_due_date)}</p></div><Badge active={financing.situation !== "QUITADO"}>{financing.situation.replace("_", " ")}</Badge></div>
      <div className="overflow-x-auto"><table className="w-full text-sm"><thead className="bg-[#f5f7f5] text-left"><tr>{["Parcela", "Vencimento", "Principal", "Juros", "Encargos", "Total", "Movimentos"].map(header => <th key={header} className="px-4 py-3">{header}</th>)}</tr></thead><tbody>
        {(installments ?? []).map(item => <tr key={item.id} className="border-t"><td className="px-4 py-3">{String(item.installment_number).padStart(2, "0")}/{String(financing.installment_count).padStart(2, "0")}</td><td className="px-4 py-3">{date(item.due_date)}</td><td className="px-4 py-3">{formatBRL(String(item.principal_amount))}</td><td className="px-4 py-3">{formatBRL(String(item.interest_amount))}</td><td className="px-4 py-3">{formatBRL(String(item.other_charges_amount))}</td><td className="px-4 py-3 font-medium">{formatBRL(total(item.principal_amount, item.interest_amount, item.other_charges_amount))}</td><td className="px-4 py-3 space-x-2">{item.principal_entry_id && <Link className="text-[#17643b] underline" href={`/app/${organizationSlug}/lancamentos/${item.principal_entry_id}`}>Principal</Link>}{item.interest_entry_id && <Link className="text-[#17643b] underline" href={`/app/${organizationSlug}/lancamentos/${item.interest_entry_id}`}>Juros</Link>}</td></tr>)}
      </tbody></table></div>
    </Card>
    {contract.credit_entry_id && <Card className="mt-5 p-5"><h2 className="font-semibold">Movimentação de entrada</h2><Link className="mt-2 inline-block text-sm text-[#17643b] underline" href={`/app/${organizationSlug}/lancamentos/${contract.credit_entry_id}`}>Abrir lançamento do crédito</Link></Card>}
    <Card className="mt-5 p-5"><h2 className="font-semibold">Auditoria e política</h2><p className="mt-2 text-sm text-[#667269]">Liquidações e reversões permanecem no histórico dos lançamentos vinculados. Juros e encargos nunca reduzem o saldo de principal.</p></Card>
  </>;
}
