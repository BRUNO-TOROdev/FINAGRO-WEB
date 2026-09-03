"use server";
import { revalidatePath } from "next/cache";
import { redirect } from "next/navigation";
import { z } from "zod";
import { requirePermission } from "@/lib/auth/server";
import { createClient } from "@/lib/supabase/server";
import { userMessage } from "@/lib/errors/user-message";

const schema = z.object({ name: z.string().trim().min(2), taxId: z.string().trim().max(30), partyType: z.enum(["FORNECEDOR","CLIENTE","AMBOS","BENEFICIARIO","OUTRO"]), email: z.union([z.literal(""), z.email()]), phone: z.string().trim().max(40) });
export async function saveParty(slug: string, id: string | null, formData: FormData) {
  const parsed=schema.safeParse(Object.fromEntries(["name","taxId","partyType","email","phone"].map(k=>[k,formData.get(k)])));
  if(!parsed.success) redirect(`/app/${slug}/contrapartes?erro=Revise os dados da contraparte.`);
  try { const org=await requirePermission(slug,"parties.manage"); const supabase=await createClient(); const p=parsed.data; const record={name:p.name,tax_id:p.taxId||null,party_type:p.partyType,email:p.email||null,phone:p.phone||null}; const q=id?supabase.from("parties").update(record).eq("id",id).eq("organization_id",org.id):supabase.from("parties").insert({...record,organization_id:org.id}); const {error}=await q;if(error)throw error; }
  catch(e){redirect(`/app/${slug}/contrapartes?erro=${encodeURIComponent(userMessage(e))}`)} revalidatePath(`/app/${slug}/contrapartes`);redirect(`/app/${slug}/contrapartes?sucesso=Contraparte salva com sucesso.`);
}
export async function setPartyActive(slug:string,id:string,isActive:boolean){try{const org=await requirePermission(slug,"parties.manage");const s=await createClient();const{error}=await s.from("parties").update({is_active:isActive}).eq("id",id).eq("organization_id",org.id);if(error)throw error}catch(e){redirect(`/app/${slug}/contrapartes?erro=${encodeURIComponent(userMessage(e))}`)}revalidatePath(`/app/${slug}/contrapartes`)}
