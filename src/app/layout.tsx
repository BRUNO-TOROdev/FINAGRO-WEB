import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: { default: "FINAGRO", template: "%s | FINAGRO" },
  description: "Gestão financeira rural com segurança e clareza.",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="pt-BR"><body>{children}</body></html>;
}
