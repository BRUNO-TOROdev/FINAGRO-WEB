import Link from "next/link";

export function AuthShell({ title, subtitle, children, footer }: { title: string; subtitle: string; children: React.ReactNode; footer?: React.ReactNode }) {
  return <main className="grid min-h-screen lg:grid-cols-[1.05fr_.95fr]">
    <section className="hidden bg-[#123d28] p-12 text-white lg:flex lg:flex-col lg:justify-between">
      <Link href="/" className="text-xl font-bold tracking-[.2em]">FINAGRO</Link>
      <div className="max-w-lg"><p className="mb-4 text-sm font-semibold uppercase tracking-[.18em] text-[#9bc4aa]">Gestão financeira rural</p><h1 className="text-5xl font-semibold leading-tight">Decisões mais seguras começam com números confiáveis.</h1><p className="mt-6 text-lg leading-8 text-[#c9dacf]">Organize a operação por empresa, fazenda e safra com uma base preparada para governança.</p></div>
      <p className="text-sm text-[#9fb8a7]">FINAGRO Web</p>
    </section>
    <section className="flex items-center justify-center p-6 sm:p-12"><div className="w-full max-w-md"><div className="mb-8 lg:hidden"><span className="font-bold tracking-[.2em] text-[#174d32]">FINAGRO</span></div><h2 className="text-3xl font-semibold tracking-tight">{title}</h2><p className="mt-2 text-[#667269]">{subtitle}</p><div className="mt-8">{children}</div>{footer && <div className="mt-7 text-sm text-[#667269]">{footer}</div>}</div></section>
  </main>;
}
