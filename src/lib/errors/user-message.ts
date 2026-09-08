export function userMessage(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  if (message.includes("PERMISSION_DENIED") || message.includes("row-level security")) return "Você não tem permissão para realizar esta ação.";
  if (message.includes("duplicate key")) return "Já existe um registro com esses dados.";
  if (message.includes("SELF_ROLE_CHANGE_NOT_ALLOWED")) return "Você não pode alterar o próprio perfil.";
  if (message.includes("ONLY_OWNER_CAN_ASSIGN_OWNER")) return "Somente um proprietário pode atribuir esse perfil.";
  if (message.includes("CHART_ACCOUNT_HIERARCHY_CYCLE") || message.includes("CANNOT_PARENT_ITSELF")) return "A conta pai escolhida criaria um ciclo na hierarquia.";
  if (message.includes("CHART_ACCOUNT_PARENT_NOT_FOUND")) return "A conta pai não pertence a esta organização.";
  if (message.includes("ALLOCATION_RULE_MUST_TOTAL_100")) return "Uma regra ativa deve totalizar exatamente 100,00%.";
  if (message.includes("ALLOCATION_RULE_DUPLICATE_FARM")) return "Uma fazenda não pode aparecer duas vezes na mesma regra.";
  if (message.includes("PERCENTAGE_OUT_OF_RANGE")) return "Cada percentual deve ser maior que zero e no máximo 100%.";
  if (message.includes("FARM_NOT_FOUND_IN_ORGANIZATION") || message.includes("CROP_SEASON_NOT_FOUND_IN_ORGANIZATION")) return "A fazenda ou safra informada não pertence a esta organização.";
  if (message.includes("MANUAL_ENTRY_STATUS") || message.includes("PAID_ENTRY")) return "O status PAGO é derivado de liquidação e não pode ser informado manualmente.";
  if (message.includes("AMOUNT_MUST_BE_POSITIVE") || message.includes("FINANCIAL_ENTRY_AMOUNT")) return "O valor deve ser maior que zero.";
  if (message.includes("ACTIVE_ALLOCATION_RULE_MUST_MATCH_ENTRY_SEASON")) return "A regra de rateio deve estar ativa e pertencer à mesma safra do lançamento.";
  if (message.includes("ACTIVE_CHART_ACCOUNT") || message.includes("ACTIVE_COUNTERPARTY") || message.includes("ACTIVE_BANK_ACCOUNT") || message.includes("ACTIVE_PAYMENT_METHOD")) return "Um cadastro selecionado está inativo ou pertence a outra organização.";
  if (message.includes("INSTALLMENT_TOTAL_MUST_MATCH_PLAN")) return "A soma das parcelas deve ser exatamente igual ao valor total do plano.";
  if (message.includes("DUPLICATE_INSTALLMENT") || message.includes("INSTALLMENT_NUMBERS")) return "A numeração das parcelas deve ser única e contínua.";
  if (message.includes("SETTLEMENTS_CANNOT_EXCEED")) return "A baixa ultrapassa o saldo em aberto do lançamento.";
  if (message.includes("REVERSAL_REASON_REQUIRED")) return "Informe o motivo da reversão.";
  if (message.includes("PAID_ENTRY_STATUS") || message.includes("SCHEDULE_STATUS")) return "PAGO é um estado derivado e não pode ser alterado manualmente.";
  if (message.includes("ACCOUNT_WITHOUT_MANAGERIAL_MAPPING")) return "Conta sem classificação gerencial para esta estrutura.";
  if (message.includes("PUBLISHED_BUDGET_VERSION_IS_IMMUTABLE")) return "A versão publicada é imutável. Crie uma nova revisão para alterar o planejamento.";
  if (message.includes("BUDGET_MONTH_OUTSIDE_PLAN")) return "O mês informado está fora do período do orçamento.";
  return "Não foi possível concluir a operação. Revise os dados e tente novamente.";
}
