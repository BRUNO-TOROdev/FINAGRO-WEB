# Homologação de importação FINAGRO

Modelo de relatório para cada lote. Não registrar PII nem valores detalhados de lançamentos neste documento versionado.

## Identificação

- Organização:
- Hash SHA-256 do arquivo:
- Aba: `Base de Dados`
- Período fechado:
- Responsável pela análise:
- Data:

## Reconciliação

| Métrica | Origem | Staging | Importado | Diferença |
|---|---:|---:|---:|---:|
| Linhas |  |  |  |  |
| Entradas |  |  |  |  |
| Saídas |  |  |  |  |

Registrar também contagens e totais por mês, status, Fazenda/rateio e conta do Plano de Contas. Toda diferença deve possuir justificativa e severidade.

## Pendências e transformações

- Mapeamentos explícitos utilizados:
- Linhas bloqueadas:
- Alertas aceitos:
- `GERAL` convertido por regra formal `GENERAL`, vigente na data e independente de Safra:
- Registros `PAGO`: vencimento pode ser usado somente como `DUE_DATE_SURROGATE`, com aviso de data não confirmada, banco mapeado e liquidação integral única.
- Surrogates não comprovam Caixa Efetivo nem conciliação bancária; correção exige reversão e nova liquidação `CONFIRMED`.

## Aprovação

- Dry-run revisado: [ ]
- Cobertura e totais reconciliados: [ ]
- Sem bloqueios: [ ]
- Confirmação autorizada: [ ]
- Plano de reversão revisado: [ ]
