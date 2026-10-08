import { z } from "zod";

export const allocationRuleHeaderSchema = z.object({
  name: z.string().trim().min(2, "Informe o nome da regra.").max(140),
  cropSeasonId: z.uuid("Selecione uma safra.").optional(),
  description: z.string().trim().max(500).optional(),
});
