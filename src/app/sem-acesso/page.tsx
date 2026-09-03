import Link from "next/link";
import { ShieldX } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card } from "@/components/ui/card";

export default function AccessDeniedPage() {
  return <main className="flex min-h-screen items-center justify-center p-6"><Card className="max-w-lg p-10 text-center"><ShieldX className="mx-auto mb-5 size-12 text-[#8a3b31]" /><h1 className="text-2xl font-semibold">Acesso não autorizado</h1><p className="mt-3 text-[#667269]">Sua conta não possui acesso ativo a esta organização. Nenhum dado foi disponibilizado.</p><Button asChild className="mt-7"><Link href="/app">Voltar às organizações</Link></Button></Card></main>;
}
