import { z } from "zod";

export const chartAccountSchema = z.object({
  code: z.string().trim().min(1, "Informe o código.").max(40),
  name: z.string().trim().min(2, "Informe o nome da conta.").max(160),
  parentId: z.union([z.uuid(), z.literal("")]).optional(),
  managerialType: z.enum(["RECEITA", "CUSTO", "DESPESA", "INVESTIMENTO", "FINANCIAMENTO", "TRANSFERENCIA", "SALDO_INICIAL", "OUTRO"]),
  nature: z.enum(["ENTRADA", "SAIDA", "NEUTRA"]),
  displayOrder: z.coerce.number().int().min(0).max(999999),
});
