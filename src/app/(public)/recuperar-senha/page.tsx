import Link from "next/link";
import { AuthShell } from "@/components/auth/auth-shell";
import { Notice } from "@/components/feedback/notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { requestPasswordReset } from "@/features/auth/actions";

export default async function RecoveryPage({ searchParams }: { searchParams: Promise<{ erro?: string; sucesso?: string }> }) {
  const params = await searchParams;
  return <AuthShell title="Recupere sua senha" subtitle="Enviaremos um link seguro para redefinição." footer={<Link className="font-semibold text-[#174d32]" href="/login">Voltar ao login</Link>}><Notice error={params.erro} success={params.sucesso} /><form action={requestPasswordReset} className="space-y-5"><label className="block text-sm font-medium">E-mail<Input className="mt-2" type="email" name="email" required /></label><Button className="w-full">Enviar instruções</Button></form></AuthShell>;
}
