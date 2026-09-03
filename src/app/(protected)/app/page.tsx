import Link from "next/link";
import { redirect } from "next/navigation";
import { Building2 } from "lucide-react";
import { requireUser } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { Card } from "@/components/ui/card";

export default async function OrganizationsPage() {
  const user = await requireUser();
  const supabase = await createClient();
  const { data } = await supabase.from("memberships").select("id,organizations!inner(id,legal_name,trade_name,slug,is_active)").eq("user_id", user.id).eq("is_active", true);
  const organizations = (data ?? []).map((item) => item.organizations as unknown as { id: string; legal_name: string; trade_name: string | null; slug: string; is_active: boolean }).filter((item) => item.is_active);
  if (organizations.length === 1) redirect(`/app/${organizations[0].slug}`);
  return <main className="min-h-screen bg-[#eef2ef] p-6 sm:p-12"><div className="mx-auto max-w-4xl"><span className="font-bold tracking-[.2em] text-[#174d32]">FINAGRO</span><div className="mt-16"><p className="text-sm font-semibold uppercase tracking-[.16em] text-[#397356]">Ambiente de trabalho</p><h1 className="mt-3 text-4xl font-semibold tracking-tight">Escolha uma organização</h1><p className="mt-3 text-[#667269]">Somente organizações com vínculo ativo são exibidas.</p></div>{organizations.length === 0 ? <Card className="mt-10 p-8"><h2 className="font-semibold">Sem organização disponível</h2><p className="mt-2 text-sm text-[#667269]">Sua conta está autenticada, mas ainda não possui membership ativa. Solicite acesso a um administrador.</p></Card> : <div className="mt-10 grid gap-4 sm:grid-cols-2">{organizations.map((organization) => <Link key={organization.id} href={`/app/${organization.slug}`} className="group"><Card className="flex items-center gap-4 p-5 transition group-hover:border-[#76a88b] group-hover:shadow-md"><div className="rounded-lg bg-[#e3eee7] p-3 text-[#174d32]"><Building2 className="size-5"/></div><div><h2 className="font-semibold">{organization.trade_name || organization.legal_name}</h2><p className="mt-1 text-xs text-[#78837b]">Acessar ambiente</p></div></Card></Link>)}</div>}</div></main>;
}
