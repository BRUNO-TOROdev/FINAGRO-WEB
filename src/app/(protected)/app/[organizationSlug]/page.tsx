import { CalendarRange, MapPinned, ShieldCheck } from "lucide-react";
import { Card } from "@/components/ui/card";
import { PageHeading } from "@/components/layout/page-heading";
import { requireOrganizationMembership } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";

export default async function OverviewPage({ params }: { params: Promise<{ organizationSlug: string }> }) {
  const { organizationSlug } = await params;
  const organization = await requireOrganizationMembership(organizationSlug);
  const supabase = await createClient();
  const [{ count: farms }, { count: seasons }] = await Promise.all([
    supabase.from("farms").select("id", { count: "exact", head: true }).eq("organization_id", organization.id).eq("is_active", true),
    supabase.from("crop_seasons").select("id", { count: "exact", head: true }).eq("organization_id", organization.id).eq("is_active", true),
  ]);
  const cards = [{ label: "Fazendas ativas", value: farms ?? 0, icon: MapPinned }, { label: "Safras ativas", value: seasons ?? 0, icon: CalendarRange }, { label: "Perfil de acesso", value: organization.roleName, icon: ShieldCheck }];
  return <><PageHeading eyebrow="Visão geral" title={`Olá, bem-vindo à ${organization.trade_name || organization.legal_name}`} description="Esta fundação reúne os cadastros operacionais e o controle de acesso da sua organização."/><div className="grid gap-4 md:grid-cols-3">{cards.map((card) => <Card key={card.label} className="p-6"><div className="mb-8 flex size-10 items-center justify-center rounded-lg bg-[#e4eee7] text-[#174d32]"><card.icon className="size-5"/></div><p className="text-sm text-[#667269]">{card.label}</p><p className="mt-2 text-2xl font-semibold">{card.value}</p></Card>)}</div><Card className="mt-6 p-6"><h2 className="font-semibold">Base pronta para crescer</h2><p className="mt-2 max-w-3xl text-sm leading-6 text-[#667269]">A navegação respeita seu vínculo e suas permissões no banco. Módulos financeiros permanecem fora desta entrega, conforme o escopo aprovado.</p></Card></>;
}
