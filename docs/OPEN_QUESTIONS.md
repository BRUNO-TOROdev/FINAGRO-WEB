# Questões abertas

## Data de liquidação dos registros históricos `PAGO`

**Afeta:** importação da Base de Dados FINAGRO e criação de settlements.

**Comportamento observado:** a fonte registra status `PAGO`, mas não fornece, de forma homologada, uma data inequívoca de liquidação. Data de emissão e vencimento têm outras semânticas e não podem ser usadas silenciosamente.

- Alternativa A — usar vencimento como data de liquidação, explicitamente aprovado para o lote.
- Alternativa B — exigir arquivo complementar com a data efetiva.
- Alternativa C — importar inicialmente sem settlement e manter a linha bloqueada até saneamento.

**Impacto:** saldo pago/em aberto, caixa efetivo futuro, auditoria e reversões. Até decisão humana, `PAGO` recebe `PAID_SETTLEMENT_POLICY_REQUIRED` e impede a confirmação do lote.
