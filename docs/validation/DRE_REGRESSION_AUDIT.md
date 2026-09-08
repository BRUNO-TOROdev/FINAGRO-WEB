# Auditoria de regressão estrutural — DRE realizado

## Fontes e privacidade

Foram comparadas a aba `DRE` da planilha FINAGRO em branco, a estrutura da
`Base de Dados`, o mapeamento gerencial V1 e, somente para confirmação de
estrutura, a versão preenchida local. Nenhum valor financeiro, lançamento,
nome, documento, contraparte ou dado pessoal foi copiado ou versionado.

O oráculo foi fórmula + estrutura da base + mappings confirmados. Valores
cacheados de fórmulas não foram usados como verdade.

## Evidências confirmadas

- Linhas analíticas verificadas: 107 linhas da DRE, incluindo grupos e detalhe.
- Linhas calculadas verificadas: 10.
- Meses verificados nas fórmulas: 12, mais total anual.
- Competência: `Base_Período_DRE`, derivado da data de emissão.
- Status: não aparece como critério nas fórmulas `SUMIFS`; `PENDENTE`,
  `AGENDADO` e `PAGO` participam da competência.
- Liquidações: não alimentam a DRE.
- Total por Fazenda: no SaaS usa `entry_allocations`, e não percentuais fixos.
- Sinais: valores analíticos são positivos; operadores explícitos da estrutura
  somam receitas e subtraem deduções, custos, despesas, impostos e dividendos.

## Reconciliação das linhas calculadas

1. Receita Operacional Bruta = Receita Operacional.
2. Receita Operacional Líquida = Receita Bruta − Deduções.
3. Lucro Bruto = Receita Líquida − Custos.
4. Margem de Contribuição = Lucro Bruto − Despesas Variáveis.
5. EBIT = Margem de Contribuição − Despesas Operacionais.
6. Resultado Financeiro Líquido = Receitas Financeiras − Despesas Financeiras − Juros de Financiamentos.
7. Resultado Não Operacional = Receitas Não Operacionais − Despesas Não Operacionais.
8. EBT = EBIT + Resultado Financeiro + Resultado Não Operacional.
9. Lucro Líquido = EBT − Imposto de Renda.
10. Lucro Retido = Lucro Líquido − Dividendos.

Cada lançamento é associado a um único mapping por estrutura. Pais analíticos
podem apresentar o subtotal dos descendentes, mas a fórmula de resultado agrega
os lançamentos por papel gerencial uma única vez.

## Divergências estruturais explicadas

- Percentuais históricos 45/15/40, exceções de 70% e variações entre blocos não
  foram reproduzidos. Diferença esperada por correção estrutural aprovada:
  snapshots reais de apropriação são a fonte atual.
- A fórmula histórica de juros que usa período de fluxo não foi reproduzida.
  Toda a DRE realizada usa emissão, conforme regra de produto homologada.
- Fórmula cross-block, referências quebradas e caches antigos foram ignorados.
- Transferências e `Entradas_Não_Operacionais` continuam sem mapping. Havendo
  movimento, aparecem na cobertura e não são somadas arbitrariamente em Outros.

## Resultado

**PASS — equivalência estrutural confirmada**, ressalvadas as diferenças
esperadas e já aprovadas acima. A validação automatizada usa somente fixtures
sintéticas e verifica competência, status, cálculos, apropriações, cobertura,
precisão monetária e isolamento multi-tenant.
