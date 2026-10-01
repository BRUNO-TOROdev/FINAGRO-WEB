# Auditoria de regressão — Dashboard gerencial

## Fonte e método

- Arquivo: `source-local/FINAGRO - Planilha Financeira (Em branco).xlsx`.
- Abas inspecionadas programaticamente: `Dashboard I`, `Dashboard 2`, `Dashboard 3`, `Dashboard 4` e `Dashboard 5`, incluindo fórmulas, desenhos, imagens, séries e intervalos de gráficos.
- Valores cacheados não foram usados como evidência financeira e nenhum dado operacional foi versionado.

## Evidência histórica

| Painel | Estrutura encontrada | Fonte comprovada | Tratamento no Web |
|---|---|---|---|
| Dashboard I | Gráfico mensal “Receitas e Despesas” | Meses `DRE!C6:N6`, receitas `DRE!C7:N7`, custos/despesas derivados de `DRE!C140:N140 - DRE!C7:N7` | Mantido conceitualmente como KPIs e evolução mensal da DRE, usando report-line IDs/códigos estáveis |
| Dashboard 2 | Saldo inicial, entradas, saídas, geração e saldo acumulado | `Fluxo de Caixa!C7:N7`, `C30:N30`, `C157`, `C159:N159`, `C162:N162` | Mantido pela engine homologada de DFC por vencimento |
| Dashboard 3 | Repetição do bloco do Dashboard 2 | Mesmos intervalos de Fluxo de Caixa | Consolidado em uma única visão executiva |
| Dashboard 4 | Repetição do bloco do Dashboard 2 | Mesmos intervalos de Fluxo de Caixa | Consolidado em uma única visão executiva |
| Dashboard 5 | Repetição do bloco do Dashboard 2 | Mesmos intervalos de Fluxo de Caixa | Consolidado em uma única visão executiva |

O pacote contém um gráfico Excel nativo legível em `Dashboard I`; as demais abas preservam fórmulas auxiliares e imagens, mas não séries de gráfico nativas recuperáveis. Não foram encontrados filtros próprios confiáveis nos cinco painéis. Slicers existentes no workbook pertencem a estruturas auxiliares e vários nomes estão quebrados (`#N/A`/`#REF!`), portanto não foram promovidos a regras.

## Composição homologada

- Resultado econômico: `get_realized_dre` ou `get_realized_dre_crop_season`, conforme escolha explícita.
- Caixa: `get_realized_cash_flow`, sempre por `due_date` e nunca por settlements.
- Comparação: `get_projected_vs_actual`, apenas com versão `PUBLICADO` escolhida explicitamente.
- Cobertura: objetos retornados pelas próprias engines.
- Uma RPC de composição reduz round-trips, mas não lê `financial_entries`, não agrega valores e não contém regras de DRE/DFC.

## Modernizações deliberadas

- Uma página responsiva substitui cinco painéis repetitivos.
- Período, Fazenda, orçamento e base DRE ficam visíveis e persistem na URL.
- “GERAL” não é Fazenda; o consolidado resulta dos snapshots de `entry_allocations` nas engines.
- Saldo final usa o total `LAST` da engine; saldos mensais jamais são somados no frontend.
- Desvio sem projetado permanece `N/A` e não recebe interpretação verde/vermelha.
- Alertas são exclusivamente técnicos: cobertura, orçamento ausente, seleção sazonal incompleta e erro de consulta.

## Itens descartados ou adiados

- Layout literal do Excel, imagens decorativas, slicers quebrados e painéis duplicados.
- Próximos vencimentos foi mantido como navegação para Lançamentos; uma nova consulta operacional foi deliberadamente evitada neste MVP.
- Caixa efetivo por settlement, conciliação e julgamentos automáticos de performance permanecem fora do escopo.

**Resultado estrutural: PASS.**
