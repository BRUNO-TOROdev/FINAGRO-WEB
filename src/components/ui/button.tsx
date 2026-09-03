import * as React from "react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "@/lib/cn";

const styles = cva("inline-flex h-10 items-center justify-center rounded-lg px-4 text-sm font-semibold transition-colors disabled:pointer-events-none disabled:opacity-50", {
  variants: { variant: {
    default: "bg-[#174d32] text-white hover:bg-[#0d3521]",
    outline: "border bg-white text-[#26332a] hover:bg-[#eef3ef]",
    ghost: "text-[#34453a] hover:bg-[#e8eee9]",
    danger: "bg-[#9b2c2c] text-white hover:bg-[#7c2222]",
  } }, defaultVariants: { variant: "default" },
});

export function Button({ className, variant, asChild, ...props }: React.ButtonHTMLAttributes<HTMLButtonElement> & VariantProps<typeof styles> & { asChild?: boolean }) {
  const Component = asChild ? Slot : "button";
  return <Component className={cn(styles({ variant }), className)} {...props} />;
}
