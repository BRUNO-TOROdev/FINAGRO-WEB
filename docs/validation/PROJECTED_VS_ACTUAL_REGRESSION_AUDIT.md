# Auditoria de regressão — Projetado × Realizado

## Decisão homologada

| Visão | Projetado | Realizado | Base temporal |
|---|---|---|---|
| `DRE_COMPETENCIA` | Projeção DRE da versão publicada selecionada | DRE realizado | emissão |
| `DRE_SAFRA` | Projeção DRE da versão publicada selecionada | DRE Safra | ciclo de Safra/Safrinha |
| `DFC_VENCIMENTO` | Projeção DFC da versão publicada selecionada | Fluxo de Caixa FINAGRO | vencimento |

A versão publicada é sempre selecionada explicitamente. Linhas são alinhadas por correspondências versionadas entre UUIDs de `report_line_templates`; nomes de contas, nomes de origem e posições físicas do Excel não participam da engine.

## Desvio e zero

O desvio absoluto é `realizado - projetado`, e o percentual é `realizado / projetado - 1`. Para `0 / 0`, o resultado é `0%`. Com projetado zero e realizado não zero, o percentual é indisponível e aparece o alerta “Realizado sem valor projetado”. Com realizado zero, o resultado é `-100%`.

No DFC, saldo inicial usa o primeiro mês e saldo final usa o último mês; saldos mensais não são somados. A cobertura e os alertas da engine realizada são preservados. Nenhum item sem mapping é lançado em “Outros”. A comparação é agregada no PostgreSQL e usa snapshots de apropriação de lançamentos e orçamentos.

As fontes históricas confirmam Projeção DRE × DRE Safra, mas a FINAGRO Web também oferece DRE por competência por decisão humana homologada. O caixa preserva Projeção DFC × realizado por vencimento e não consulta settlements. Nenhum valor financeiro ou dado pessoal da planilha foi versionado.
