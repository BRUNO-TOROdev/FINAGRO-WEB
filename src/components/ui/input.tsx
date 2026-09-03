import * as React from "react";
import { cn } from "@/lib/cn";

export function Input({ className, ...props }: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input className={cn("h-10 w-full rounded-lg border bg-white px-3 text-sm shadow-sm placeholder:text-[#849087] focus:border-[#2c6e49] focus:ring-2 focus:ring-[#2c6e49]/15", className)} {...props} />;
}
