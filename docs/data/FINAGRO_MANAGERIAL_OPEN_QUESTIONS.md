# Questões abertas — homologação gerencial FINAGRO

Somente os itens abaixo exigem validação humana. Nenhum deles foi promovido a mapping operacional definitivo.

## 1. Período dos juros de financiamento na DRE

- Conta/regra: `Empréstimos_e_Financiamentos → Juros`.
- Observado: a linha está dentro da DRE, mas a fórmula usa `Base_Período_Fluxo` (vencimento), enquanto as demais linhas analíticas usam `Base_Período_DRE` (emissão).
- Evidência: fórmulas da DRE e DRE Safra na planilha em branco, confirmadas estruturalmente na preenchida.
- Alternativa A: tratar como erro histórico e usar emissão na futura DRE.
- Alternativa B: preservar vencimento como exceção explícita.
- Impacto: altera o mês de reconhecimento dos juros na futura DRE.

## 2. Período da Comissão no Fluxo de Caixa

- Conta/regra: `Despesas_Variáveis → Comissão`.
- Observado: no Fluxo de Caixa em branco, a fórmula usa período da DRE; as demais saídas usam período do Fluxo.
- Evidência: fórmula da linha Comissão na aba Fluxo de Caixa.
- Alternativa A: usar vencimento, mantendo a regra geral do DFC previsto.
- Alternativa B: preservar emissão como exceção explícita.
- Impacto: altera a posição mensal da comissão no futuro DFC.

## 3. Escopo da DRE Safra fora dos custos agrícolas

- Conta/regra: todas as linhas da DRE Safra exceto `Custos_com_Materiais_Agricultura`.
- Observado: elas usam período de emissão, mas não usam `Base_Período_Safra`; somente os custos agrícolas combinam Safra + Safrinha e período anterior.
- Evidência: fórmulas completas da DRE Safra em branco e estrutura confirmada na preenchida.
- Alternativa A: preservar a exceção histórica apenas para custos agrícolas.
- Alternativa B: definir uma nova política de Safra para outras linhas antes de implementar o relatório.
- Impacto: determina quais receitas/despesas entram na futura DRE Safra.

## 4. Transferências entre contas

- Conta/regra: Grupo `Transferência_Entre_Contas` e filhos Entrada/Saída.
- Observado: existem no cadastro, mas não aparecem nas estruturas consolidadas de DRE ou Fluxo de Caixa inspecionadas.
- Alternativa A: manter fora de DRE e DFC consolidado, tratando como movimento interno neutro.
- Alternativa B: exibir apenas em visão bancária/por conta, com eliminação na consolidação.
- Impacto: evita dupla contagem de entrada e saída; condiciona o futuro desenho de transferências e conciliação.

## 5. Entradas Não Operacionais sem lista válida

- Conta/regra: Grupo `Entradas_Não_Operacionais`.
- Observado: o Grupo existe, não possui Subgrupos oficiais e o nome definido correspondente contém `#REF!`; a estrutura usa `Receitas_Não_Operacionais` em seu lugar.
- Alternativa A: manter sem mapping até definição funcional.
- Alternativa B: homologar uma linha específica e finalidade distinta.
- Impacto: determina se a conta poderá participar de DFC/projeção e como será classificada.

## 6. Calcário e Gesso na fórmula sazonal

- Conta/regra: `Custos_com_Materiais_Agricultura → Calcário` e `→ Gesso`.
- Observado: a aba `DRE SAFRA` em branco aplica a mesma combinação Safra +
  Safrinha, mês corrente + mesmo mês do ano anterior, às seis subcontas do grupo.
  O checkpoint de produto homologou explicitamente quatro: Adubo, Fretes sobre
  Matéria Prima, Produtos Quimicos e Sementes.
- Evidência: fórmulas C29:C34, repetidas até N29:N34. C30 e C32 possuem os mesmos
  quatro `SUMIFS` e critérios de C29, C31, C33 e C34.
- Alternativa A: homologar Calcário e Gesso como sazonais.
- Alternativa B: manter somente as quatro contas indicadas pelo produto.
- Impacto: define se lançamentos dessas duas contas usam o recorte de Safra +
  Safrinha e o período anterior ou permanecem bloqueados por configuração sazonal ausente.
