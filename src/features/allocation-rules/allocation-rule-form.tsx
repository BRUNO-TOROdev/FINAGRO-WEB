"use client";

import { useMemo, useState } from "react";
import { AlertCircle, CheckCircle2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { formatPercentageTotal, ONE_HUNDRED_PERCENT, percentageToMicros } from "./decimal";
import type { AllocationRuleFormInitial } from "./form-model";

type FarmOption = { id: string; name: string; is_active: boolean };
type SeasonOption = { id: string; name: string; is_active: boolean };

export function AllocationRuleForm({ action, farms, seasons, initial }: {
  action: (formData: FormData) => void | Promise<void>;
  farms: FarmOption[];
  seasons: SeasonOption[];
  initial?: AllocationRuleFormInitial;
}) {
  const [values, setValues] = useState<Record<string, string>>(initial?.percentages ?? {});
  const [active, setActive] = useState(initial?.isActive ?? false);
  const [scope, setScope] = useState<"SEASONAL"|"GENERAL">(initial?.scope ?? (initial?.cropSeasonId ? "SEASONAL" : "GENERAL"));
  const calculation = useMemo(() => {
    try {
      const total = Object.values(values).filter((value) => value.trim() !== "").reduce((sum, value) => sum + percentageToMicros(value), 0n);
      return { total, valid: true };
    } catch { return { total: 0n, valid: false }; }
  }, [values]);
  const exact = calculation.valid && calculation.total === ONE_HUNDRED_PERCENT;

  return <form action={action} className="mt-5 space-y-6">
    {initial && <input type="hidden" name="scope" value={scope}/>}<div className="grid gap-4 md:grid-cols-2"><label className="text-sm font-medium">Nome<Input name="name" className="mt-2" defaultValue={initial?.name} required /></label><label className="text-sm font-medium">Tipo<select name={initial ? undefined : "scope"} value={scope} disabled={Boolean(initial)} onChange={e=>setScope(e.target.value as "SEASONAL"|"GENERAL")} className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm disabled:bg-[#f3f5f3]"><option value="SEASONAL">Por Safra</option><option value="GENERAL">Geral da organização</option></select></label>{scope==="SEASONAL"?<label className="text-sm font-medium">Safra<select name="cropSeasonId" defaultValue={initial?.cropSeasonId ?? ""} required className="mt-2 h-10 w-full rounded-lg border bg-white px-3 text-sm"><option value="" disabled>Selecione</option>{seasons.map((season) => <option key={season.id} value={season.id}>{season.name}{season.is_active ? "" : " (inativa)"}</option>)}</select></label>:<><label className="text-sm font-medium">Vigência inicial<Input name="effectiveFrom" type="date" className="mt-2" defaultValue={initial?.effectiveFrom??""} required/></label><label className="text-sm font-medium">Vigência final (opcional)<Input name="effectiveTo" type="date" className="mt-2" defaultValue={initial?.effectiveTo??""}/></label></>}</div>
    <label className="block text-sm font-medium">Descrição<Input name="description" className="mt-2" defaultValue={initial?.description} /></label>
    <div><div className="mb-3 flex items-end justify-between"><div><h3 className="font-semibold">Distribuição</h3><p className="mt-1 text-sm text-[#667269]">Informe percentuais com até 6 casas decimais.</p></div><div className={`text-right ${exact ? "text-emerald-700" : "text-amber-700"}`}><p className="text-xs font-semibold uppercase tracking-wider">Total</p><p className="text-xl font-semibold">{calculation.valid ? formatPercentageTotal(calculation.total) : "Inválido"}%</p></div></div><div className="divide-y rounded-lg border">{farms.map((farm) => { const hasValue = Boolean(initial?.percentages[farm.id]); return <label key={farm.id} className={`flex items-center gap-4 px-4 py-3 ${!farm.is_active && !hasValue ? "opacity-50" : ""}`}><span className="min-w-0 flex-1 text-sm font-medium">{farm.name}{!farm.is_active && <span className="ml-2 text-xs text-[#78837b]">Inativa</span>}</span><Input name={`percentage:${farm.id}`} value={values[farm.id] ?? ""} disabled={!farm.is_active && !hasValue} onChange={(event) => { const next = { ...values, [farm.id]: event.target.value }; setValues(next); try { const total = Object.values(next).filter(Boolean).reduce((sum, value) => sum + percentageToMicros(value), 0n); if (total !== ONE_HUNDRED_PERCENT) setActive(false); } catch { setActive(false); } }} inputMode="decimal" placeholder="0,00" className="w-32 text-right"/><span className="text-sm text-[#667269]">%</span></label>; })}</div></div>
    <div className={`flex items-start gap-3 rounded-lg border p-4 ${exact ? "border-emerald-200 bg-emerald-50" : "border-amber-200 bg-amber-50"}`}>{exact ? <CheckCircle2 className="mt-0.5 size-5 text-emerald-700"/> : <AlertCircle className="mt-0.5 size-5 text-amber-700"/>}<div className="flex-1"><p className="text-sm font-semibold">{exact ? "Distribuição completa" : "A regra ainda está em rascunho"}</p><p className="mt-1 text-sm">{exact ? "O total permite ativar a regra." : "A ativação exige exatamente 100,00%."}</p></div><label className="flex items-center gap-2 text-sm font-semibold"><input type="checkbox" name="isActive" checked={exact && active} disabled={!exact} onChange={(event) => setActive(event.target.checked)} />Ativa</label></div>
    <Button type="submit">{initial ? "Salvar alterações" : "Criar regra"}</Button>
  </form>;
}
