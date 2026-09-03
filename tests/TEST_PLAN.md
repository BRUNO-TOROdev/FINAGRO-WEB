# FINAGRO Web — Plano de Testes da Fundação de Banco v0.2

## Objetivo
Validar integridade financeira, isolamento multi-tenant, rateio por safra, liquidações e preservação histórica antes de qualquer interface financeira ser desenvolvida.

## Critério de bloqueio
Nenhuma tela de lançamentos financeiros deve ser considerada pronta enquanto os testes P0 abaixo não estiverem automatizados e verdes no ambiente local do Supabase.

## P0 — Isolamento entre organizações
1. Criar Usuário A ligado somente à Organização A.
2. Criar Usuário B ligado somente à Organização B.
3. Criar uma fazenda, safra, conta, contraparte, banco e lançamento em cada organização.
4. Autenticar como A e comprovar que nenhum SELECT retorna registros da B.
5. Autenticar como A e tentar INSERT/UPDATE usando IDs pertencentes à B; a operação deve falhar.
6. Repetir o cenário inverso com B.
7. Cobrir no mínimo: farms, crop_seasons, chart_accounts, allocation_rules, parties, bank_accounts, financial_entries, entry_allocations, settlements, financing_contracts, budgets.

## P0 — Status
- Aceitar somente PENDENTE, AGENDADO, PAGO.
- Recusar qualquer outro valor.
- Recusar alteração manual para PAGO sem liquidação integral.
- Ao atingir liquidação integral, alterar automaticamente para PAGO.
- Ao reverter a liquidação integral, retornar a PENDENTE; RPC pode restaurar AGENDADO quando solicitado.

## P0 — Regra de rateio
- Regra inativa pode existir com percentuais incompletos enquanto está sendo editada.
- Ativação com 99,99% deve falhar.
- Ativação com 100,00% deve funcionar.
- Percentual individual <= 0 ou > 100 deve falhar.
- Fazenda de outra organização deve falhar por FK composta.
- Safra de outra organização deve falhar por FK composta.

## P0 — Snapshot do rateio
Cenário:
1. Regra Safra 2026/27 = A 45%, B 40%, C 15%.
2. Aplicar a lançamento de R$ 100.000,00.
3. Confirmar apropriações 45.000 / 40.000 / 15.000.
4. Alterar a regra futura para 40 / 40 / 20.
5. O lançamento histórico deve continuar 45.000 / 40.000 / 15.000.
6. Novo lançamento deve receber 40.000 / 40.000 / 20.000.

## P0 — Arredondamento do rateio
- Valor R$ 100,00 com 33,333333% / 33,333333% / 33,333334% deve totalizar exatamente R$ 100,00.
- O resíduo de centavos deve ser absorvido deterministicamente pela última linha ordenada da regra.
- Soma de entry_allocations.allocated_amount deve ser exatamente igual a financial_entries.amount.

## P0 — Apropriação de lançamento
- Lançamento direto em uma fazenda = 100% naquela fazenda.
- Lançamento em mais de uma fazenda sem regra de rateio deve falhar.
- Lançamento rateado deve utilizar somente uma regra por snapshot.
- Não misturar rateio + apropriação direta no mesmo lançamento.
- Regra de rateio deve pertencer à mesma safra do lançamento.
- Alterar a safra de uma regra já utilizada deve falhar.

## P0 — Plano de contas
- Conta de outra organização deve falhar.
- Conta inativa não pode ser selecionada em novo lançamento.
- Conta com requires_crop_season=true exige Safra.
- Conta historicamente usada deve poder ser inativada sem alterar lançamentos antigos.

## P0 — Liquidações
- Soma das liquidações ativas nunca pode ultrapassar o valor do lançamento.
- Liquidação é imutável; correção = reversão + nova liquidação.
- Reversão exige usuário, data e justificativa.
- Liquidação não pode ser criada para lançamento excluído logicamente.
- Liquidação de organização diferente deve falhar.

## P0 — Parcelamento
- installment_plan não possui impacto financeiro próprio.
- N parcelas devem somar exatamente o total do plano.
- Relatórios devem considerar apenas financial_entries das parcelas.
- Um plano de R$ 500.000 em cinco parcelas de R$ 100.000 deve gerar R$ 500.000 nos relatórios, nunca R$ 1.000.000.

Observação: a soma das parcelas ao total do plano ainda deve ser formalizada em um serviço/RPC de geração de parcelamento; a tabela por si só não força esse total no v0.2.

## P1 — Financiamentos
- Entrada do financiamento é lançamento separado de amortização.
- Principal e juros geram lançamentos distintos.
- Parcela não pode referenciar lançamento de outra organização.
- Cronograma deve preservar número da parcela e vencimento.

## P1 — Orçamento
- Orçamento DRE e DFC são independentes.
- budget_item.period_month deve ser sempre o primeiro dia do mês.
- Apropriações do orçamento devem totalizar o valor do item.
- Projetado x Realizado deve respeitar organização, fazenda, safra, conta e mês.

Observação: a invariante de 100% para budget_item_allocations será implementada junto ao serviço de orçamento, espelhando a regra de entry_allocations.

## P1 — Relatórios
- DRE usa issue_date.
- Fluxo previsto usa due_date.
- Extrato/fluxo realizado usa settlement.settled_at.
- Saídas têm sinal negativo apenas na camada de relatório; amount permanece positivo no banco.
- Views devem usar security_invoker para não contornar RLS.

## P1 — Auditoria
Confirmar geração de log para:
- lançamento criado/editado/excluído logicamente;
- mudança de status;
- baixa e reversão;
- alteração de rateio;
- alteração de plano de contas;
- alteração de usuário/permissão.

## Teste de equivalência FINAGRO
Após a fundação do produto:
1. Criar base anonimizada a partir da planilha preenchida.
2. Importar os mesmos lançamentos.
3. Reproduzir as regras de rateio históricas aprovadas.
4. Comparar mês a mês DRE, DRE Safra, DFC, Extrato e Projetado x Realizado.
5. Diferença não explicada = falha de regressão.
