import { AuthShell } from "@/components/auth/auth-shell";
import { Notice } from "@/components/feedback/notice";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { updatePassword } from "@/features/auth/actions";

export default async function ResetPage({ searchParams }: { searchParams: Promise<{ erro?: string }> }) {
  const params = await searchParams;
  return <AuthShell title="Defina uma nova senha" subtitle="Use ao menos 8 caracteres."><Notice error={params.erro} /><form action={updatePassword} className="space-y-5"><label className="block text-sm font-medium">Nova senha<Input className="mt-2" type="password" name="password" minLength={8} required /></label><Button className="w-full">Salvar nova senha</Button></form></AuthShell>;
}
