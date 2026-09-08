import { cn } from "@/lib/cn";

export function Badge({ active = true, className, children }: { active?: boolean; className?: string; children: React.ReactNode }) {
  return <span className={cn("inline-flex rounded-full px-2.5 py-1 text-xs font-semibold", active ? "bg-[#e0f0e6] text-[#175c38]" : "bg-[#ecefed] text-[#647068]", className)}>{children}</span>;
}
