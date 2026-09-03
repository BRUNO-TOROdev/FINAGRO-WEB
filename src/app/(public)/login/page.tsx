import Link from "next/link";
import { AuthShell } from "@/components/auth/auth-shell";
import { Notice } from "@/components/feedback/notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { login } from "@/features/auth/actions";

export default async function LoginPage({ searchParams }: { searchParams: Promise<{ erro?: string }> }) {
  const { erro } = await searchParams;
  return <AuthShell title="Acesse sua conta" subtitle="Entre com seu e-mail corporativo para continuar." footer={<>Problemas para acessar? <Link className="font-semibold text-[#174d32]" href="/recuperar-senha">Recuperar senha</Link></>}>
    <Notice error={erro} />
    <form action={login} className="space-y-5"><label className="block text-sm font-medium">E-mail<Input className="mt-2" type="email" name="email" autoComplete="email" required /></label><label className="block text-sm font-medium">Senha<Input className="mt-2" type="password" name="password" autoComplete="current-password" minLength={8} required /></label><Button className="w-full" type="submit">Entrar</Button></form>
  </AuthShell>;
}
