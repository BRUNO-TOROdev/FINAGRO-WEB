# Auditoria do mapeamento gerencial FINAGRO V1

## Escopo e fontes

Foram analisadas programaticamente as 154 contas (27 Grupos e 127 Subgrupos) do template oficial. A fonte canônica foi `source-local/FINAGRO - Planilha Financeira (Em branco).xlsx`. O arquivo local `FINAGRO - Planilha Financeira (Preenchida).xlsx` foi usado somente para confirmar fórmulas, referências, nomes definidos, blocos e estrutura; nenhum valor, lançamento, nome, documento, contraparte ou dado pessoal foi extraído ou versionado.

As fórmulas e a estrutura da Base de Dados prevaleceram sobre caches de células. O arquivo canônico completo, inclusive a relação Grupo → Subgrupos e a evidência por conta, é `finagro-managerial-mapping-v1.json`.

## Evidências de período

- `Base_Data_Emissão` aponta para a data de emissão e `Base_Período_DRE` para o período derivado usado na DRE.
- `Base_Data_Vencimento` aponta para a data de vencimento e `Base_Período_Fluxo` para o período usado no Fluxo de Caixa previsto.
- `Base_Período_Safra`, `Safra` e `Safrinha` são critérios explícitos da lógica especial da DRE Safra.

## Estrutura encontrada — DRE

Ordem conceitual preservada:

1. Receita Operacional Bruta: Receita da Agricultura + Receita da Pecuária.
2. Deduções da Receita: Impostos sobre Faturamento + Cancelamentos e Devoluções.
3. Receita Operacional Líquida.
4. Custos: Materiais Agricultura + Materiais Pecuária.
5. Lucro Bruto.
6. Despesas Variáveis e Margem de Contribuição.
7. Despesas Agricultura/Pecuária e Despesas Administrativas Gerais.
8. EBIT.
9. Resultado Financeiro Líquido: Receitas Financeiras − Despesas Financeiras − Juros de Empréstimos/Financiamentos.
10. Resultado Não Operacional.
11. EBT, Imposto de Renda, Lucro Líquido, Dividendos e Lucro Retido.

As linhas de resultado, margem e subtotais são linhas calculadas de relatório, não contas. Investimentos, entrada e principal de financiamentos, transferências e saldo inicial não integram a DRE observada.

## Estrutura encontrada — Fluxo de Caixa previsto

O Fluxo de Caixa usa vencimento e possui estrutura própria:

- Entradas: receitas agrícolas/pecuárias, entrada de financiamento, receitas financeiras e não operacionais.
- Saídas: deduções, custos, despesas, investimentos, principal e juros de financiamentos, imposto de renda e dividendos.
- Geração de Caixa, Saldo Inicial e Saldo de Caixa Acumulado são linhas calculadas/de saldo.

Principal e juros aparecem em linhas distintas. O principal participa do fluxo, mas não da DRE observada. O valor contratual do financiamento não é uma terceira movimentação.

## DRE Safra

A árvore visual é a da DRE, mas o cálculo não equivale a aplicar um filtro de Safra a toda a DRE. Apenas `Custos_com_Materiais_Agricultura` possui, de forma sistemática, quatro agregações: Safra e Safrinha, no mês corrente e no mês deslocado em 13 meses. As demais linhas analíticas observadas continuam usando o período da DRE sem critério de Safra.

Nos blocos históricos por fazenda, valores classificados como `GERAL` recebem percentuais fixos. Esses percentuais variam entre blocos e há fórmulas copiadas de modo inconsistente. Eles não foram migrados. No sistema, a fonte operacional permanece `allocation_rules` por Safra, com snapshot em `entry_allocations`.

## Projeções

A planilha em branco contém uma projeção com árvore de caixa. A versão preenchida separa Projeção DRE e Projeção DFC. O mapeamento inicial replica somente a participação estrutural comprovada nas respectivas árvores; nenhum valor projetado foi importado e nenhum motor de orçamento foi criado.

## Financiamentos e transferências

- Entrada de financiamento: entrada no DFC, fora da DRE observada.
- Principal: saída no DFC, fora da DRE observada.
- Juros: saída no DFC e linha financeira na DRE, com anomalia de período descrita nas questões abertas.
- Tarifas, seguros e outros encargos não possuem linhas específicas comprovadas na planilha oficial; continuam classificados explicitamente por conta no módulo de financiamentos.
- `Transferência_Entre_Contas` não aparece nas árvores inspecionadas da DRE ou do Fluxo de Caixa consolidado. Não foi promovida a receita/despesa nem recebeu mapping operacional.

## Resultado da classificação

- Contas analisadas: 154.
- Contas com classificação estrutural confirmada pela planilha: 150.
- Contas mantidas pendentes: 4 (`Transferência_Entre_Contas`, seus dois filhos, e `Entradas_Não_Operacionais`).
- Mappings operacionais confirmados entre as cinco estruturas: 666.
- Regras inferidas promovidas ao banco: zero.

Os campos legados `OUTRO`/`NEUTRA` do plano não foram reescritos. A classificação gerencial passou a existir em tabelas de estruturas, linhas e mappings independentes, sempre por UUID. Nomes são evidência auditável, nunca chave de execução.

## Anomalias confirmadas

1. A linha `Juros` de financiamentos na DRE e DRE Safra usa `Base_Período_Fluxo`, divergindo da regra geral por emissão.
2. A linha `Comissão` do Fluxo de Caixa em branco usa `Base_Período_DRE`, divergindo da regra geral por vencimento.
3. Há referências nomeadas quebradas (`Entradas_Não_Operacionais`, `GRUPO_BANCOS`, `GRUPO_PERÍODO` e slicers legados).
4. Em um bloco por fazenda da DRE Safra preenchida, uma fórmula de custo agrícola referencia células de outro bloco. A anomalia não foi corrigida nem convertida em regra.
5. Percentuais históricos de `GERAL` são fixos nas fórmulas e variam por bloco; não representam regra permanente do SaaS.
6. A versão preenchida contém contas adicionais próprias. Elas foram deliberadamente excluídas do template oficial de 154 contas.

## Confiança e operacionalização

Os mappings carregados usam `confirmed_spreadsheet`. Ocorrências `inferred_needs_validation` permanecem apenas no arquivo canônico e nas questões abertas. Não há regra baseada em `display_name` ou `source_name`.
