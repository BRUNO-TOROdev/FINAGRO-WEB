"use client";
import NextLink from "next/link";
import { usePathname } from "next/navigation";

export function FinancialEntryLink(props: React.ComponentProps<typeof NextLink>) {
  const pathname = usePathname();
  const href = typeof props.href === "string" && props.href.startsWith("?visualizar=")
    ? `${pathname}/${new URLSearchParams(props.href.slice(1)).get("visualizar")}`
    : props.href;
  return <NextLink {...props} href={href} />;
}
