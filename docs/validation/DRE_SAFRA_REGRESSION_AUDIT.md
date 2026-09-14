# Auditoria de regressão estrutural — DRE Safra

## Fonte, método e privacidade

Foi analisada programaticamente a aba `DRE SAFRA` de
`source-local/FINAGRO - Planilha Financeira (Em branco).xlsx`, incluindo fórmulas,
referências e nomes definidos. A análise não importou valores, lançamentos,
pessoas, documentos ou contrapartes. Fórmulas e estrutura tiveram precedência
sobre valores cacheados.

## Regra temporal reconstruída

A planilha exibe doze meses reais em C6:N6. Nas linhas sazonais, cada célula soma
quatro agregações: Safra no mês exibido, Safra em `EOMONTH(mês,-13)+1`, Safrinha
no mês exibido e Safrinha no mesmo deslocamento. Como as datas são o primeiro dia
do mês, `EOMONTH(mês,-13)+1` equivale ao primeiro dia do mesmo mês do ano anterior.

No sistema, essa fórmula foi traduzida para:

1. ciclo exibido = meses entre `starts_on` e `ends_on` da Safra principal;
2. ciclos selecionados = UUID da Safra principal + UUID da Safrinha;
3. mês sazonal = mês de emissão atual + mesmo mês deslocado 12 meses para trás;
4. linha regular = somente mês de emissão atual, sem filtro global de Safra.

## Classificação das linhas

- Sazonais homologadas: Adubo, Fretes sobre Matéria Prima, Produtos Quimicos e
  Sementes. A execução usa IDs de template, mapping e conta organizacional.
- Regulares: demais mappings sem regra sazonal. Usam emissão no ciclo exibido.
- Calculadas: dez linhas da DRE, derivadas por operandos explícitos e sem conta lançável.

## Divergências e anomalias

- **Requer validação humana:** Calcário e Gesso também contêm os quatro `SUMIFS`
  sazonais na planilha, mas não constam entre as quatro contas homologadas pelo
  checkpoint. Não receberam regra definitiva. Se usados, são sinalizados como
  mapping com configuração sazonal ausente.
- **Diferença esperada por correção estrutural:** percentuais fixos, exceções de
  70% e diferenças entre blocos por Fazenda não foram reproduzidos. A fonte é o
  snapshot de `entry_allocations`.
- **Anomalia histórica:** referências cross-block, quebradas e caches antigos não
  participam da engine.
- **Equivalência confirmada:** status não é critério, vencimento e settlement não
  definem competência, e linhas não sazonais não recebem filtro de Safra.

## Resultado

**PASS com uma pendência explícita.** A equivalência das quatro contas autorizadas,
do ciclo atravessando anos, das linhas regulares, das fórmulas calculadas e das
apropriações foi automatizada. Calcário e Gesso aguardam decisão humana e não foram
silenciosamente convertidos em regra operacional.
