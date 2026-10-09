"use client";

export default function GlobalError({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <html lang="pt-BR">
      <body>
        <main className="mx-auto flex min-h-screen max-w-xl flex-col items-center justify-center gap-4 px-6 text-center">
          <h1 className="text-2xl font-semibold">Não foi possível concluir a operação</h1>
          <p className="text-sm text-slate-600">
            Tente novamente. Se o problema continuar, informe o horário da ocorrência ao suporte.
          </p>
          <button
            className="rounded-md bg-emerald-700 px-4 py-2 text-sm font-medium text-white"
            onClick={reset}
            type="button"
          >
            Tentar novamente
          </button>
        </main>
      </body>
    </html>
  );
}
