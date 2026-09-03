import { cn } from "@/lib/cn";

export function Card({ className, ...props }: React.HTMLAttributes<HTMLDivElement>) {
  return <div className={cn("rounded-xl border bg-white shadow-[0_1px_2px_rgba(20,42,27,.04)]", className)} {...props} />;
}
