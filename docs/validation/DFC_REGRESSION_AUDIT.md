# Auditoria de regressão estrutural — Fluxo de Caixa FINAGRO

## Fonte e método

A aba `Fluxo de Caixa` da planilha FINAGRO em branco foi reanalisada
programaticamente. Foram inspecionadas fórmulas, referências e nomes definidos.
Nenhum valor financeiro, lançamento, pessoa, documento ou contraparte foi
importado ou versionado. Fórmulas e estrutura prevaleceram sobre caches.

## Estrutura confirmada

- Meses: doze posições mensais, com totais anuais.
- Linhas analíticas: contas mapeadas explicitamente para `DFC_PREVISTO`.
- Total de entradas: soma das contas configuradas como `ENTRADA`.
- Total de saídas: soma das contas configuradas como `SAIDA`.
- Geração de caixa: entradas menos saídas.
- Saldo inicial: no primeiro mês, conta de abertura `SALDO_INICIAL`; nos meses
  seguintes, saldo final do mês anterior.
- Saldo de caixa acumulado: saldo inicial do mês mais geração de caixa.

As linhas calculadas não são contas lançáveis. A conta de saldo inicial informa
somente a abertura; ela não é receita e não compõe o total de entradas.

## Período, status e apropriações

As fórmulas analíticas usam `Base_Período_Fluxo`, derivado da data de vencimento.
STATUS não aparece como critério: `PENDENTE`, `AGENDADO` e `PAGO` participam.
Settlement e data de emissão não definem o mês. Fazenda e consolidado usam
exclusivamente snapshots de `entry_allocations`.

## Financiamentos e parcelamentos

Entrada do financiamento, principal e juros aparecem em contas analíticas
separadas. O valor contratual e o plano de parcelamento não entram na engine;
somente `financial_entries` reais participam, impedindo dupla contagem.

## Pendências e anomalias

- Transferência Entre Contas e Entradas Não Operacionais continuam sem mapping;
  quando utilizadas, aparecem na cobertura e não são classificadas como receita
  ou despesa.
- A fórmula da Comissão usa isoladamente `Base_Período_DRE`, enquanto as demais
  linhas do DFC usam `Base_Período_Fluxo`. Foi classificada como
  `historical_anomaly`; a regra homologada da engine permanece vencimento.
- Percentuais fixos históricos e caches de fórmulas não participam do cálculo.

## Resultado

**PASS — equivalência estrutural confirmada.** A validação automatizada usa
fixtures sintéticas e cobre período, status, saldos, financiamento, apropriações,
cobertura, precisão monetária e isolamento multi-tenant.
