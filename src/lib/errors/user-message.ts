export function userMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("PERMISSION_DENIED") || message.includes("row-level security")) return "Você não tem permissão para realizar esta ação.";
  if (message.includes("duplicate key")) return "Já existe um registro com esses dados.";
  if (message.includes("SELF_ROLE_CHANGE_NOT_ALLOWED")) return "Você não pode alterar o próprio perfil.";
  if (message.includes("ONLY_OWNER_CAN_ASSIGN_OWNER")) return "Somente um proprietário pode atribuir esse perfil.";
  return "Não foi possível concluir a operação. Revise os dados e tente novamente.";
}
