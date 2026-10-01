# Questões abertas

## Data de liquidação dos registros históricos `PAGO` — resolvida em 2026-10-01

**Afeta:** importação da Base de Dados FINAGRO e criação de settlements.

**Decisão homologada:** quando a fonte registra `PAGO` sem data efetiva conhecida, `due_date` será usada exclusivamente como substituta técnica, com `date_basis=DUE_DATE_SURROGATE`. Essa data não representa confirmação bancária nem evidência de Caixa Efetivo.

- Banco/conta precisam estar mapeados; sem correspondência segura, a linha permanece bloqueada.
- Sem vencimento válido, a linha permanece bloqueada.
- Correção futura exige reversão do surrogate e nova liquidação `CONFIRMED`; settlements não são editados.

**Impacto futuro:** Caixa Efetivo e conciliação bancária devem excluir esses registros por padrão ou apresentá-los separadamente como data não confirmada.

## Rateios do primeiro piloto

Permanece aberta a associação entre cada Safra encontrada em registros `GERAL` de janeiro/2026 e uma `allocation_rule` formal. Nenhuma regra ou percentual será inferido.
