"use server";

import { redirect } from "next/navigation";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";
import { getSiteUrl } from "@/lib/supabase/env";

const credentials = z.object({ email: z.email(), password: z.string().min(8) });

export async function login(formData: FormData) {
  const parsed = credentials.safeParse({ email: formData.get("email"), password: formData.get("password") });
  if (!parsed.success) redirect("/login?erro=Informe e-mail e senha válidos.");
  const supabase = await createClient();
  const { error } = await supabase.auth.signInWithPassword(parsed.data);
  if (error) redirect("/login?erro=E-mail ou senha inválidos.");
  redirect("/app");
}

export async function logout() {
  const supabase = await createClient();
  await supabase.auth.signOut();
  redirect("/login");
}

export async function requestPasswordReset(formData: FormData) {
  const email = z.email().safeParse(formData.get("email"));
  if (!email.success) redirect("/recuperar-senha?erro=Informe um e-mail válido.");
  const siteUrl = getSiteUrl();
  const supabase = await createClient();
  await supabase.auth.resetPasswordForEmail(email.data, {
    redirectTo: new URL("/auth/callback?next=/redefinir-senha", siteUrl).toString(),
  });
  redirect("/recuperar-senha?sucesso=Se o e-mail estiver cadastrado, você receberá as instruções.");
}

export async function updatePassword(formData: FormData) {
  const password = z.string().min(8).safeParse(formData.get("password"));
  if (!password.success) redirect("/redefinir-senha?erro=A senha deve ter pelo menos 8 caracteres.");
  const supabase = await createClient();
  const { error } = await supabase.auth.updateUser({ password: password.data });
  if (error) redirect("/redefinir-senha?erro=O link expirou. Solicite uma nova recuperação.");
  redirect("/app");
}
