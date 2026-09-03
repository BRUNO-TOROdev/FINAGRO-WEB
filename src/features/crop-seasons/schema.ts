import { z } from "zod";

export const cropSeasonSchema = z.object({
  name: z.string().trim().min(2, "Informe o nome da safra.").max(120),
  seasonType: z.enum(["PRINCIPAL", "SAFRINHA", "OUTRA"]),
  cropName: z.string().trim().max(80).optional(),
  startsOn: z.string().optional(),
  endsOn: z.string().optional(),
}).refine((data) => !data.startsOn || !data.endsOn || data.endsOn >= data.startsOn, {
  message: "A data final deve ser igual ou posterior à data inicial.",
});
