import Link from "next/link";
import { Building2, CalendarRange, ChartNoAxesCombined, ChevronDown, CircleDollarSign, FileChartColumnIncreasing, GitBranch, HandCoins, Home, Landmark, ListTree, LogOut, MapPinned, ReceiptText, Users, UserRoundSearch } from "lucide-react";
import { logout } from "@/features/auth/actions";
import { Button } from "@/components/ui/button";
import type { OrganizationContext } from "@/types/database";

const links = [
  { href: "", label: "Início", icon: Home, permission: null },
  { href: "/lancamentos", label: "Lançamentos", icon: CircleDollarSign, permission: "entries.view" },
  { href: "/parcelamentos", label: "Parcelamentos", icon: ReceiptText, permission: "entries.view" },
  { href: "/financiamentos", label: "Financiamentos", icon: HandCoins, permission: "financing.view" },
  { href: "/orcamentos", label: "Orçamentos", icon: ChartNoAxesCombined, permission: "budgets.view" },
  { href: "/fazendas", label: "Fazendas", icon: MapPinned, permission: "farms.view" },
  { href: "/safras", label: "Safras", icon: CalendarRange, permission: "seasons.view" },
  { href: "/plano-de-contas", label: "Plano de Contas", icon: ListTree, permission: "chart_accounts.view" },
  { href: "/rateios", label: "Regras de Rateio", icon: GitBranch, permission: "allocation_rules.view" },
  { href: "/contrapartes", label: "Contrapartes", icon: UserRoundSearch, permission: "parties.view" },
  { href: "/contas-bancarias", label: "Contas Bancárias", icon: Landmark, permission: "bank_accounts.view" },
  { href: "/usuarios", label: "Usuários", icon: Users, permission: "users.manage" },
];

export function AppShell({ organization, userEmail, children }: { organization: OrganizationContext; userEmail: string; children: React.ReactNode }) {
  const base = `/app/${organization.slug}`;
  return <div className="min-h-screen lg:grid lg:grid-cols-[260px_1fr]">
    <aside className="border-r bg-[#123d28] px-5 py-6 text-white lg:min-h-screen">
      <div className="flex items-center justify-between"><span className="text-lg font-bold tracking-[.18em]">FINAGRO</span><span className="rounded-md bg-white/10 px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-[#b9d3c2]">Web</span></div>
      <div className="mt-8 rounded-xl border border-white/10 bg-white/5 p-3"><div className="flex gap-3"><Building2 className="mt-1 size-4 shrink-0 text-[#9bc4aa]"/><div className="min-w-0"><p className="truncate text-sm font-semibold">{organization.trade_name || organization.legal_name}</p><p className="mt-1 text-xs text-[#a9c2b1]">{organization.roleName}</p></div><ChevronDown className="ml-auto size-4 text-[#9bc4aa]" /></div></div>
      <nav className="mt-8"><p className="px-3 text-[11px] font-semibold uppercase tracking-[.16em] text-[#86aa93]">Navegação</p><div className="mt-3 space-y-1">{links.filter((item) => !item.permission || organization.permissions.includes(item.permission)).map((item) => <Link key={item.href} href={`${base}${item.href}`} className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-[#d5e3da] transition hover:bg-white/10 hover:text-white"><item.icon className="size-4" />{item.label}</Link>)}</div>{organization.permissions.includes("reports.view")&&<div className="mt-7"><p className="px-3 text-[11px] font-semibold uppercase tracking-[.16em] text-[#86aa93]">Relatórios</p><div className="mt-3 space-y-1"><Link href={`${base}/relatorios/dre`} className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-[#d5e3da] transition hover:bg-white/10 hover:text-white"><FileChartColumnIncreasing className="size-4"/>DRE</Link><Link href={`${base}/relatorios/dre-safra`} className="flex items-center gap-3 rounded-lg px-3 py-2.5 text-sm text-[#d5e3da] transition hover:bg-white/10 hover:text-white"><FileChartColumnIncreasing className="size-4"/>DRE Safra</Link></div></div>}</nav>
    </aside>
    <div className="min-w-0"><header className="flex min-h-16 items-center justify-between border-b bg-white px-5 sm:px-8"><div><p className="text-xs font-medium text-[#78837b]">Organização atual</p><p className="text-sm font-semibold">{organization.trade_name || organization.legal_name}</p></div><div className="flex items-center gap-3"><div className="hidden text-right sm:block"><p className="text-sm font-medium">{userEmail}</p><p className="text-xs text-[#78837b]">{organization.roleName}</p></div><form action={logout}><Button variant="ghost" className="px-3" title="Sair"><LogOut className="size-4"/><span className="sr-only">Sair</span></Button></form></div></header><main className="p-5 sm:p-8 lg:p-10">{children}</main></div>
  </div>;
}
