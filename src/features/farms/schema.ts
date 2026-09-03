import { z } from "zod";

export const farmSchema = z.object({
  name: z.string().trim().min(2, "Informe o nome da fazenda.").max(120),
  internalCode: z.string().trim().max(40).optional(),
  totalAreaHa: z.string().trim().regex(/^\d+(?:[.,]\d{1,4})?$/, "Informe uma área válida.").optional().or(z.literal("")),
});

export type FarmInput = z.infer<typeof farmSchema>;
