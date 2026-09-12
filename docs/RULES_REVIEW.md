# Revisão da base de regras — 30/08/2026

> Revisão regra a regra motivada pela correção apontada pelo Igor (devolução de venda no Simples espelha a nota original; o CSOSN 900 é o caso da devolução de compra). Cada regra recebeu um veredito: **OK** (lógica e base legal confirmadas), **AJUSTADA** (corrigida nesta revisão), **REMOVIDA**, ou **REDUNDANTE-SEFAZ** (a SEFAZ já rejeita — mantida com valor baixo, útil para XMLs antigos/homologação). Fontes consultadas listadas ao final.

## Princípios que a revisão reforçou

1. **Devolução não se lê só pelo CFOP.** O que define o tratamento é o conjunto: quem emite (vendedor ou comprador), `finNFe=4`, `tpNF`, CFOP 1.20x/2.20x × 5.20x/6.20x, `NFref` e a **nota original**. Por isso as regras de devolução passaram para o escopo `cross_document` e comparam com a original (`DOC.RETURN.MIRROR`), em vez de fixar um CST "certo".
2. **Regime do emitente ≠ regime do cenário.** Regras de tributação usam o regime do cenário; a divergência entre os dois é regra própria (`ICMS.CRT.SCENARIO`, `SCENARIO.REGIME.*`).
3. **Consumidor final muda tudo**: DIFAL, IPI na base do ICMS (LC 87/96 art. 13 §2), ST (não há ST a consumidor final), obrigatoriedade dos campos de ST retida (Rejeição 938 só quando `indFinal=0`), Lei 12.741.
4. **Vigência importa**: alíquota interestadual a não contribuinte só a partir de 2016 (EC 87/2015); IBS/CBS a partir de 2026; PIS/COFINS até 2026.

## Vereditos

| Regra | Veredito | Observação / base |
|---|---|---|
| `ICMS.CSOSN.SALE_RETURN` | **REMOVIDA** | Premissa errada. Devolução de venda emitida pelo optante (NF-e de entrada, finNFe 4, CFOP 1.202/2.202, NFref) espelha a venda: CSOSN 101/102 da original, sem destaque. O 900 é para devolução de **compra** (destacar o ICMS do fornecedor). Substituída por `DOC.RETURN.MIRROR`. |
| `DOC.RETURN.MIRROR` | **NOVA** | Compara item a item com a original: CST/CSOSN, alíquota, CST PIS/COFINS e CFOP correspondente (5.101→1.201, 5.102→1.202, 5.401→1.410, 5.403/5.405→1.411; 2.xxx interestadual). Vale para Simples (mesmo CSOSN) e regime normal (mesmo CST, com destaque para recuperar crédito). |
| `DOC.RETURN.ORIGINAL` | **REMOVIDA** (dividida) | Misturava "original ausente" (não é erro do cliente) com "quantidade excedida" (erro). |
| `DOC.RETURN.ORIGINAL_MISSING` | **NOVA** (warning) | Só quando a chave referenciada é do próprio cliente. |
| `DOC.RETURN.EXCEEDS_ORIGINAL` | **NOVA** (error) | Quantidade devolvida acumulada > vendida. |
| `DOC.RETURN.REFERENCE` | REDUNDANTE-SEFAZ | Rejeição 321 (finNFe 4 sem NFref). Mantida. |
| `CFOP.RETURN.PURPOSE` | OK | CFOP de devolução ⇄ finNFe 4. |
| `DOC.RETURN.CFOP_REQUIRES_REFERENCE` | OK | Tabela CFOP: `requires_reference`. |
| `ICMS.REGIME.SITUATION_FIELD` | OK | CRT 1/2/4 → CSOSN; CRT 3 → CST. |
| `ICMS.CRT.SCENARIO` | OK | |
| `CFOP.SCOPE.MATCH` / `CFOP.KNOWN` | OK | |
| `DOC.TOTALS.ITEMS_SUM`, `ICMS.AMOUNT.CALC` | REDUNDANTE-SEFAZ | NT 2015.003 (rejeições 5xx de totais e de vICMS ≠ vBC×pICMS). Mantidas. |
| `ICMS.RATE.INTERSTATE` | **AJUSTADA** | Só alcança não contribuintes a partir de 01/01/2016 (antes, alíquota interna). Origem: ver abaixo. |
| `item.icms.origin_category` (derivação) | **AJUSTADA** | Res. Senado 13/2012: 4% para origem **1, 2, 3 e 8**; 4 (PPB), 5 (≤40%), 6 e 7 (sem similar nacional) seguem 7%/12%. Estava 1, 2, 6, 7. Afeta `ICMS.RATE.INTERSTATE`, `DIFAL.INTERSTATE_RATE`, `ICMS.IMPORTED.ORIGIN_INTERSTATE`. |
| `ICMS.IMPORTED.ORIGIN_INTERSTATE` | OK (após a derivação) | |
| `ICMS.BASE.CALC` (derivação `expected_base_amount`) | **AJUSTADA** | IPI integra a base do ICMS quando a operação é a consumidor final / não contribuinte (LC 87/96 art. 13 §2 XI). |
| `PISCOFINS.CST.REGIME` | **AJUSTADA** | Simples: 49 (padrão) e 04/06/07/08 (monofásico/alíquota zero com receita segregada). Removido 99 (é de entrada). |
| `PISCOFINS.RATE.REGIME` | OK | 0,65/3,00 cumulativo; 1,65/7,60 não cumulativo (só CST 01). |
| `PISCOFINS.CST.DIRECTION`, `PISCOFINS.CST.MATCH`, `PISCOFINS.AMOUNT.CALC`, `PISCOFINS.SIMPLES.HIGHLIGHT` | OK | Vigência até 31/12/2026. |
| `PISCOFINS.SINGLE_PHASE` | **AJUSTADA** | Revenda: CST 04; fabricante/importador (cenário indústria): CST 02. |
| `IPI.NON_TAXPAYER.HIGHLIGHT`, `IPI.SIMPLES.HIGHLIGHT`, `IPI.CST.DIRECTION`, `IPI.AMOUNT.CALC`, `IPI.RATE.TIPI` | OK | CST IPI 00–49 entrada / 50–99 saída (Tabela 4.3.2). |
| `ICMS.SIMPLES.NO_HIGHLIGHT`, `ICMS.EXEMPT.HIGHLIGHT`, `ICMS.CST00.WITH_REDUCTION` | OK (baixo valor) | Os grupos ICMSSN101/102, ICMS40/60 e ICMS00 nem têm os campos no schema; só disparam em XML fora do padrão. |
| `ICMS.REDUCED_BASE.PCT_REQUIRED`, `ICMS.CST51.DEFERRAL_FIELDS` | OK | |
| `ICMS.RATE.INTERNAL` | OK | Tabela por NCM com fallback na alíquota geral; exclui redução de base. |
| `ICMS.FCP.EXPECTED` | **AJUSTADA** (dado) | FCP geral só no RJ (2%); MG/ES/SP têm FCP em NCMs específicos → `fcp_rate` geral de MG zerado. |
| `ICMS.SIMPLES.CREDIT_RATE` | OK | 1,25%–3,95% (LC 123 art. 23 §1). |
| `ICMS.SIMPLES.CREDIT_CALC` | **AJUSTADA** | Aceita base bruta ou líquida; severidade warning. |
| `ICMS.SIMPLES.CREDIT_TO_NON_TAXPAYER` | OK | Crédito só a contribuinte (LC 123 art. 23). |
| `DOC.SIMPLES.INFO_TEXT` | OK | Res. CGSN 140/2018 art. 59 §4 I. |
| `DOC.SIMPLES.CREDIT_TEXT` | **NOVA** | Res. CGSN 140/2018 art. 60: CSOSN 101/201 exige "PERMITE O APROVEITAMENTO DO CRÉDITO DE ICMS…". |
| `CFOP.ST.SUBSTITUTED_CST`, `CFOP.ST.SUBSTITUTE_CST`, `CFOP.ST.NONE_WITH_ST_CST` | OK | 5.405/6.404 ⇄ CST 60/CSOSN 500; 5.401/5.403 ⇄ 10/30/70/90 ou 201/202/203/900. |
| `ICMS.ST.CATALOG` | **AJUSTADA** | Só a contribuinte e não consumidor final (não há ST na venda a consumidor final). |
| `ICMS.ST.BASE_MVA`, `ICMS.ST.AMOUNT_CALC` | OK (warning/error) | ST = base ST × alíq − ICMS próprio. |
| `ICMS.ST.WITHHELD_FIELDS` | OK | NT 2018.005 / Rejeição 938: obrigatório quando **não** consumidor final (regra já condiciona a contribuinte). |
| `DIFAL.REQUIRED`, `DIFAL.INTERSTATE_RATE`, `DIFAL.SIMPLES` | OK | EC 87/2015; ADI 5464 (Simples). |
| `DIFAL.CALC` | **AJUSTADA** | Warning: UFs com base dupla divergem da fórmula de base única. |
| `CFOP.OWN_PRODUCTION.INDUSTRY` | **AJUSTADA** | Aceita atividade rural (5.101 do produtor). |
| `CEST.REQUIRED`, `CEST.MISMATCH`, `CEST.FORMAT` | OK | Conv. ICMS 142/18 cl. 6ª §1 (CEST mesmo sem ST na UF). |
| `NCM.VALID`, `NCM.FORMAT`, `NCM.GENERIC.GOODS` | OK | |
| `NFCE.CFOP.INTRASTATE`, `NFCE.RECIPIENT.NON_TAXPAYER` | OK | Ajuste SINIEF 07/05; NFC-e a CNPJ segue permitida (Ajuste 12/2026 revogou a proibição do 11/2025). |
| `DOC.NFCE.IDENTIFY_CONSUMER` | OK | ≥ R$ 10.000 nacional (Ajuste SINIEF 19/16); UFs com limite menor (MT R$ 1.000) → sobreposição de `params.limit`. |
| `DOC.CONSUMER.TAX_TRANSPARENCY` | OK | Lei 12.741/2012. |
| `DOC.COMPLEMENTARY.REFERENCE`, `DOC.ISSUER.UF_SCENARIO`, `DOC.ISSUER.IE_SCENARIO`, `DOC.ITEM.DISCOUNT_OVER_PRODUCT` | OK | |
| `IBSCBS.GROUP.REQUIRED` (v1/v2), `IBSCBS.CBS.RATE_SCHEDULE`, `IBSCBS.IBS.RATE_SCHEDULE`, `IBSCBS.CBS.AMOUNT_CALC`, `IBSCBS.CST.*`, `IBSCBS.CLASS_CODE.FORMAT`, `IBSCBS.NFCE.GROUP`, `IBSCBS.CST_CLASS.COHERENT` | OK | LC 214/2025 art. 343 (0,9% CBS + 0,1% IBS em 2026); NT 2025.002 v1.40 (rejeição desde 03/08/2026). |
| `IBSCBS.BASE.OPERATION_VALUE` | **AJUSTADA** | LC 214 art. 12 §2 exclui IBS/CBS, IPI, descontos e ICMS/ISS/PIS/COFINS: a base agora deve ficar entre "valor líquido − tributos embutidos" e "valor líquido"; fora disso é erro do ERP. |
| `DOC.NUMBERING.GAP`, `DOC.NUMBERING.ORDER`, `DOC.DUPLICATE.NUMBER_SERIES`, `DOC.EVENT.CONSISTENCY` | OK | Cancelamento: 24h (Ajuste SINIEF 07/05 cl. 13ª); extemporâneo varia por UF → warning. |
| `SCENARIO.ST.DISAGREEMENT` | **AJUSTADA** | Usava campo inexistente (`st.applies_any`); o cenário ganhou `st.applies` (formulário, inferência e zod). |
| `SCENARIO.REGIME.*` | **AJUSTADA** | Nova `SCENARIO.REGIME.REAL_VS_SIMPLES` (a anterior só cobria Presumido). |
| Demais `SCENARIO.*` | OK | |

## Fontes
- Devolução de venda no Simples: [Mentor Fiscal — CFOP 1.202/2.202](https://mentorfiscal.com.br/cfop-1202-2202/), [Rotina Fiscal — devolução Simples Nacional](https://www.rotinafiscal.com.br/operacoes-fiscais/devolucao-simples-nacional), [Sisgel — devoluções](https://sisgel.com/duvidas/simples-nacional-2/devolucoes/)
- Res. Senado 13/2012 e códigos de origem: [SEFAZ-RJ — perguntas frequentes](https://portal.fazenda.rj.gov.br/icms/resolucao-senado-13-2012-perguntas-frequentes/), [LEFISC SP](https://www.lefisc.com.br/news/resolucao_do_senado_13_de_2012_aliquota_interestadual_mercadorias_importadas_perguntas_e_respostas_SP.htm)
- LC 214/2025 art. 12: [Planalto](https://planalto.gov.br/ccivil_03/leis/lcp/lcp214.htm), [Simtax — base de cálculo na transição](https://simtax.com.br/base-calculo-ibs-cbs-transicao/)
- NFC-e identificação ≥ R$ 10.000: [Ajuste SINIEF 19/2016](https://www.normaslegais.com.br/legislacao/ajuste-sinief-19-2016.htm), [Ajuste SINIEF 12/2026 (revoga proibição a CNPJ)](https://inventti.com.br/ajuste-sinief-43-2025-prorroga-para-4-de-maio-de-2026-a-proibicao-de-emitir-nfc-e-quando-o-destinatario-for-cnpj/)
- Res. CGSN 140/2018 arts. 59 e 60: [SEFAZ-RJ — orientações ME/EPP](http://www.fazenda.rj.gov.br/sefaz/content/conn/UCMServer/path/Contribution%20Folders/site_fazenda/orientacoes/icms/simples/credito_icms/orient_me.html), [Receita — Res. CGSN 140](https://normas.receita.fazenda.gov.br/sijut2consulta/consulta.action?lblTiposAtosSelecionados=Res.&orgaosSelecionados=CGSN&tipoData=2&tiposAtosSelecionados=67)
- NT 2018.005 / Rejeição 938: [Oobj](https://www.oobj.com.br/bc/article/rejei%C3%A7%C3%A3o-938-n%C3%A3o-informada-vbcstret-pst-vicmssubstituto-e-vicmsstret-como-resolver-871.html), [NS Tecnologia](https://nstecnologia.com.br/blog/icms-st-retido-e-icms-efetivo)


## Adendo 31/08/2026 — validação das regras SPED contra o Guia Prático v3.2.3 (leiaute 020)

Fonte primária: PDF oficial do Guia (366 págs.), extraído e conferido registro a registro. O **leiaute completo (263 registros, todos os campos e níveis hierárquicos)** foi extraído do Guia para `api/db/data/sped_layout_020.json` e importado como `sped_layout` v2 (2026+) e v1 (2012–2025, aplicado retroativamente — importar o Guia da época se for preciso precisão histórica em registros que mudaram).

| Item validado | Veredito |
|---|---|
| Ordem dos campos C100 | **CORRIGIDA** — a spec manual omitia o campo 17 `IND_FRT`, desalinhando `VL_FRT`→`VL_COFINS_ST`. Agora os 29 campos vêm do Guia. |
| C170 (38 campos) e C190 (12) | Conferidos; campos homônimos (`ALIQ_PIS` % e em R$) recebem sufixo `_2`. |
| NFC-e na EFD | **CORRIGIDA** — modelo 65 é escriturado no **C100 nas saídas** (C860 é CF-e-SAT); a conciliação de presença agora cobre 55 e 65 (saída). |
| COD_SIT de cancelamento | **CORRIGIDA** — cancelada = **02/03**; 04 (denegada) e 05 (inutilizada) descontinuados desde 2023 e não são cancelamento. |
| Cancelada no C100 | Exceção 1: só REG…CHV_NFE, sem filhos → conferência de valores/filhos ignora COD_SIT ≠ 00/01 ✓; matching com fallback por (COD_MOD, SER, NUM_DOC) quando a chave faltar. |
| C170 em NF-e própria | Exceção 2: **regra geral não se informa C170** na NF-e de emissão própria → `SPED.ITEM.MISMATCH` só compara quando há C170 (✓ por construção). |
| C190 obrigatório | "Para cada C100… pelo menos um C190" → nova regra `SPED.DOC.NO_ANALYTIC` (COD_SIT 00/01/06/07/08 sem C190). |
| COD_SIT 08 em 2026 | Ajuste SINIEF 49/25 (notas com redução de valores na transição IBS/CBS) usa COD_SIT 08 → excluído da conferência de totais (senão viraria falso positivo em 2026). |
| Entradas | "campos de imposto só se houver direito a crédito" (enfoque do declarante) → conferência de valores restrita à emissão própria ✓. |
| C190 = consolidação dos C170 | Confirmado (por CST×CFOP×alíquota); `VL_OPR` fora da soma por incluir despesas rateadas — não comparado (evita FP). |

## Adendo 09/09/2026 — revisão das regras da revisão geral (falsos positivos/negativos provados)

Cada item foi reproduzido com `Rules::TestRunner` sobre documento canônico (`RuleCaseBuilder`) antes de decidir; cada decisão virou par de casos em `06_rule_test_cases.rb` (incluindo o caso "quase", no limite). Reverter as correções faz 14 desses casos falharem — é a prova de que testam a decisão, e não o código.

| Regra / dado | Veredito | Decisão e base |
|---|---|---|
| `ICMS.ST.AMOUNT_CALC` + derivação `icms_st.expected_amount` | **CORRIGIDA (derivação)** | Substituto optante do Simples (CSOSN 201/202/203) não destaca ICMS próprio: com `vBCST 1.400 × 18% = 252` e `vICMSST 72,00` **correto** (Conv. ICMS 35/2011 manda deduzir o ICMS que seria devido, 1.000 × 18% = 180), a derivação tratava o ICMS próprio ausente como zero e a regra apontava `error`. A dedução do optante não está no XML → o esperado deixou de ser derivado quando o item usa CSOSN (`situation_field == "csosn"`). O CST 30 (isento com ST, dedução legítima zero) continua conferido. |
| `DOC.RETURN.MIRROR` × `PISCOFINS.CST.DIRECTION` | **CORRIGIDA** | Provado: com PIS/COFINS CST 01 na devolução (entrada) dispara `PISCOFINS.CST.DIRECTION`; com CST 50 disparam dois findings de `DOC.RETURN.MIRROR` — nenhuma nota satisfazia as duas. A devolução é **entrada** e usa CST 50–99 (Tabela 4.3.3): `mirror_fields` ficou `icms.situation_code`, `icms.rate`. O espelho de PIS/COFINS não existe. |
| `CFOP.KNOWN` + tabela `cfop` | **CORRIGIDA (dado + severidade)** | 5551, 5556, 6109, 5933 e 5409 (todos legítimos) eram apontados como "CFOP inexistente" em `error`. A tabela ganhou as famílias que faltavam (513 linhas: ativo/uso e consumo 5.551–5.557, ST 5.409–5.415, transferências, devoluções 5.205–5.213, ZFM 6.109–6.116, crédito/ressarcimento, serviços, combustíveis) e vigência a partir de 01/01/2003 (Ajuste SINIEF 07/2001). Severidade → `warning`: a tabela é curadoria nossa (DATA_SOURCES §1.3, classe B, sem importador) e a SEFAZ já rejeita CFOP inexistente. **Documento anterior à vigência da tabela: refutado** — desde a correção de [M21] o derivado fica ausente e a regra nem avalia (nenhum finding, nenhum `evaluation_error`). |
| Regimes `mei` / `simples_nacional_excess` | **CORRIGIDA** | `ICMS.CRT.SCENARIO` dizia "a nota declara CRT 4 (mei), mas o cenário é mei"; `ICMS.REGIME.SITUATION_FIELD` exigia CST do MEI (que usa CSOSN). Decisão registrada em `00_helpers.rb`: **CRT 1 e 4 informam CSOSN; CRT 2 e 3 informam CST** — o excesso de sublimite recolhe ICMS/ISS fora do Simples (LC 123/2006 arts. 19 e 20), mas PIS/COFINS/IPI continuam no DAS (art. 13). Daí os três conjuntos: `simples_icms_regimes` (simples, mei), `normal_icms_regimes` (presumido, real, excesso), `simples_federal_regimes` (os três optantes). `ICMS.CRT.SCENARIO` compara CRT × regime par a par e tolera CRT 1 em cenário de excesso (ERP que ainda não atualizou o cadastro). |
| `PISCOFINS.CST.REGIME` | **CORRIGIDA** | CST 49 ("outras operações de saída") é o código correto nas saídas sem receita — remessa 5.915, transferência 5.152, bonificação 5.910, demonstração 5.912, retorno 5.902 — e a regra o rejeitava em `error` para todo Presumido/Real. Passou a cobrar 01/02/03 só quando `item.cfop_nature` é `sale` ou `export`. |
| `CFOP.RETURN.PURPOSE` | **CORRIGIDA** | O ramo "finNFe 4 com CFOP que não é de devolução" era inalcançável: `Derivations#nature` força `*_return` quando `purpose == return`. Provado com finNFe 4 + CFOP 5102 (nenhum finding). A regra passou a olhar `item.cfop_nature` dos itens e ignora documento com CFOP fora da tabela (`unknown`), para não trocar um falso negativo por um falso positivo. |
| `CFOP.ST.SUBSTITUTE_CST` × CFOP 5.410/5.411/6.410/6.411 | **CORRIGIDA** | Provado: devolução de compra de mercadoria com ST sai com CST 60 (ou CSOSN 500) e a regra apontava `error` exigindo 10/30/70/90. A prática varia por UF (algumas pedem que a devolução repita o destaque da nota de compra) — a regra passou a alcançar só `sale`/`transfer`/`bonus`; o papel `substitute` da tabela de CFOP fica intacto. |
| `IBSCBS.CBS.RATE_SCHEDULE` | **AJUSTADA (vigência)** | A alíquota de 2027 no cronograma é estimativa (`kind: "estimated"`, aguardando a Resolução do Senado) e a regra apontava `error` em 2027. v1 fechada em 31/12/2026 (alíquota-teste de 0,9% fixada na LC 214/2025 art. 343 → `error`); v2 a partir de 01/01/2027 em `warning`, dizendo que a alíquota ainda é estimativa (DATA_SOURCES §1.11). |
| `ICMS.RATE.INTERNAL` + `icms_internal_rate` RJ | **REFUTADO no dado, ajustado na severidade** | O RJ está correto na tabela: a alíquota interna geral é **20%** desde 20/03/2024 (Lei estadual 10.253/2023, que alterou o art. 14 da Lei 2.657/96), mais 2% de FECP em `pFCP` — nota do RJ com pICMS 20 + pFCP 2 **não dispara** (provado); a que dispara é a de pICMS 18. Ninguém deve "corrigir de volta" para 18. Duas ressalvas viraram mudança: a versão da tabela vale desde 01/01/2024 e antecipa em ~3 meses o aumento do RJ; e a cobertura por NCM é parcial (DATA_SOURCES §1.6), então mercadoria com alíquota específica aparece como divergência sem estar errada → severidade `warning` e mensagem com uma alíquota esperada só (`coalesce(by_ncm, geral)`, sem o "—18.00"). |
| `ICMS.IMPORTED.ORIGIN_INTERSTATE` | **REMOVIDA** | Repetia `ICMS.RATE.INTERSTATE` (que já busca 4,00 na tabela para `origin_category = imported`) sem as guardas de vigência (EC 87/2015) e de destinatário: dois findings no mesmo item. Os casos de origem 1 (4%) e origem 6 (fora da Res. 13/2012) passaram para `ICMS.RATE.INTERSTATE`. |
| `IBSCBS.NFCE.GROUP` | **REMOVIDA** | `IBSCBS.GROUP.REQUIRED` v2 já alcança todo item de mercadoria (modelos 55 e 65) a partir de 03/08/2026. |
| Doze regras redundantes com a SEFAZ | **AJUSTADAS (severidade + explicação)** | `DOC.RETURN.REFERENCE` (passou a aceitar `refNF` de nota modelo 1), `DOC.TOTALS.ITEMS_SUM`, `ICMS.AMOUNT.CALC`, `NFCE.RECIPIENT.NON_TAXPAYER`, `DOC.COMPLEMENTARY.REFERENCE` (idem `refNF`), `IBSCBS.GROUP.REQUIRED` v2, `ICMS.REDUCED_BASE.PCT_REQUIRED`, `ICMS.CST00.WITH_REDUCTION`, `CEST.FORMAT`, `NCM.FORMAT`, `ICMS.SIMPLES.NO_HIGHLIGHT`, `ICMS.EXEMPT.HIGHLIGHT` → `warning`, cada uma com `explanation` dizendo qual rejeição da SEFAZ já cobre o caso e por que, num XML autorizado, o achado costuma ser leitura nossa. |
| `ICMS.ST.WITHHELD_FIELDS` | **AJUSTADA** | A NT 2018.005 (rejeição 938) condiciona em `indFinal = 0`, não em destinatário contribuinte: a regra passou a usar `doc.operation.final_consumer == false`. Caso novo: CST 60 a consumidor final sem os campos não dispara. |
| `DIFAL.SIMPLES` | **AJUSTADA (base legal)** | Fundamentos completos: ADI 5464 (cautelar de 2016, cláusula nona do Conv. 93/2015), ADI 5469/Tema 1093 (2021) e LC 190/2022, que disciplinou o DIFAL sem instituí-lo para os optantes. Continua `info`: há UF que ainda exige por norma própria. |
| `SCENARIO.IPI.DISAGREEMENT` | **CORRIGIDA** | `evidence` comparava `item.ipi.amount` com `gt` sem `present`: item sem grupo IPI (ausência ≠ zero) virava `evaluation_error` do run. Varredura nas demais regras do lote: só `ICMS.FCP.EXPECTED` tinha o mesmo padrão (corrigido); as outras já usam `present`/`eq`, que aceitam ausência. |

Casos de teste ganharam os limites que faltavam: NFC-e de R$ 10.000,00 exatos (dispara) × R$ 9.999,99 (não dispara), pCredSN 1,25% e 3,95% (piso e teto, não disparam) × 1,24% (dispara), ICMS-ST com diferença de 0,05 dentro da tolerância, e `IBSCBS.GROUP.REQUIRED` v2 passou a ser testada dentro da vigência (15/08/2026).

## Adendo 09/09/2026 (noite) — revisão em sessão cega da própria revisão

Segunda passada, em sessão cega, sobre o resultado da revisão acima. Cada item foi reproduzido com `Rules::TestRunner` + `RuleCaseBuilder` **antes** de qualquer mudança e virou par de casos em `06_rule_test_cases.rb` (reverter as correções faz 7 desses casos falharem).

| Regra / dado | Veredito | Decisão e base |
|---|---|---|
| tabela `cfop`: 5.402/6.402 | **CORRIGIDA (dado)** | Estavam como `st_role: substitute` e `CFOP.ST.SUBSTITUTE_CST` (`error`) exigia CST 10/30/70/90. Mas 5.402 é "venda de produção do estabelecimento de produto sujeito a ST **em operação entre contribuintes substitutos do mesmo produto**": não há retenção (Convênio ICMS 142/2018, cláusula nona, I) e o CST correto é 00. Provado (dispara `error` com CST 00) e movido para o papel novo `st_other`, que nenhuma regra de ST alcança. Controle: 5.401 com CST 00 continua disparando. |
| tabela `cfop`: família 5.408–5.415 / 6.408–6.415 | **CORRIGIDA (dado)** | 5.409/6.409 (transferência de mercadoria adquirida de terceiros **sujeita a ST**) estavam com `st_role: none` e disparavam `CFOP.ST.NONE_WITH_ST_CST` (`error`) na nota legítima com CST 60/CSOSN 500 (provado nos dois códigos). 5.408/6.408 nem existiam na tabela. A família passou a ser mapeada por inteiro: 408/409 transferência e 414/415 remessa para venda fora do estabelecimento em `st_other` (cláusula nona, II: transferência entre estabelecimentos do mesmo titular não tem retenção, salvo destinatário varejista — o CST depende do caso); 410–413 (devolução de compra com ST) todas em `substitute`, como já estavam 410/411, papel que nenhuma regra de ST alcança em `purchase_return`. |
| tabela `cfop`: x.205, x.206, x.207, x.213 | **CORRIGIDA (dado)** | Classificados como devolução (`purchase_return`/`sale_return`), faziam `CFOP.RETURN.PURPOSE` (`error`) exigir `finNFe = 4` em nota de **anulação de valor** (serviço de comunicação, transporte, energia elétrica e ressarcimento de ICMS-ST), que sai com finNFe 1/2/3 — provado com 5.205 e 5.213. Natureza passou a `other`, que nenhuma regra de CFOP julga. Controle: 5.202 (devolução de compra) com finNFe 1 continua disparando. Não há NF-e com esses CFOPs nos clientes de teste (54/55): a prova é o caso canônico + o Anexo do Ajuste SINIEF s/nº 1970. |
| `PISCOFINS.CST.REGIME` | **CORRIGIDA** | O ramo novo lia `item.cfop_nature` com `not_in` sem guardar a ausência: com a tabela `cfop` sem versão vigente na data (antes de 01/01/2003) o run registrava `evaluation_error` silencioso em vez de finding (provado: `field item.cfop_nature absent for op not_in`). O ramo passou a aceitar `absent` — sem saber se a saída é venda, não se acusa o CST 49, o mesmo tratamento já dado ao CFOP fora da tabela (`unknown`). |
| `DOC.RETURN.MIRROR` (`cfop_mirror`) | **AJUSTADA (dado) + limite documentado** | A primitiva pula em silêncio quando o CFOP da venda não está no mapa (falso negativo). Entraram os pares que faltavam e são inequívocos: 6.107→2.201, 6.108→2.202, ZFM/ALC 5.109/6.109→1.201/2.201 e 5.110/6.110→1.202/2.202, ativo imobilizado 5.551/6.551→1.553/2.553. **A cobertura segue intencionalmente parcial** (consignação 5.111–5.116, conta e ordem 5.117–5.123, energia/comunicação): cada par novo exige conferir o CFOP de devolução no Anexo, e preferimos o falso negativo ao falso positivo em `error`. Registrado aqui para ninguém tratar o silêncio como bug. |
| `SPED.DOC.MISSING_IN_FILE` | **AJUSTADA (mensagem)** | A mensagem enunciava os dois diagnósticos opostos ("nota autorizada sem C100; **ou** C100 sem XML") sem dizer qual ocorreu. Voltou o `{{problem}}` (`missing_in_file` × `not_in_xml`) e o título passou a citar os dois casos. **Pendente**: separar em duas regras, com severidades próprias, exige que a primitiva `sped_document_reconciliation` aceite um `check` por diagnóstico (hoje `presence` emite os dois, e só `not_in_xml` popula `line` — daí "linha —" no outro caso). |
| `SPED.DOC.CANCELLED_SIT` | **AJUSTADA (mensagem)** | Dizia "esperado 02" enquanto o param aceita `02` e `03` (cancelamento extemporâneo). O esperado passou a ser renderizado do próprio dado (`{{params.cancelled_cod_sit}}` → "02, 03"). |
| Doze regras que passaram de `error` a `warning` na **mesma** versão | **MANTIDO (decisão registrada)** | Opção (b) — não abrir versão N+1 para cada uma. Razões medidas em 09/09/2026: (1) o banco de dev não tem **nenhum** finding das doze regras (`Audit::Finding.where(rule_code: [...]).group(:rule_code).count` → `{}`, num total de 5.811 findings), então nenhum finding emitido aponta para definição que mudou; (2) não existe base de produção nem configuração de deploy — a licença está codificada em `seed_pre_golive_env?` e, fora de dev/test, `seed_rule!` levanta exceção; (3) doze versões novas de regras que nunca julgaram documento real inflariam o catálogo que o contador lê em `docs/RULES.md`. A partir do go-live a regra é versão N+1, como já foi feito em `IBSCBS.CBS.RATE_SCHEDULE` — registrado em `DSL_RULES.md` §11. |
| Tabela `cfop` v1 reescrita no lugar | **CORRIGIDA (helper)** | `seed_table!` tinha `return if table.versions.exists?`: em banco já semeado a curadoria nova (513 → 515 linhas, colunas novas, vigência 2003) não era aplicada **em silêncio**. Agora, em `development`/`test`, a v1 criada pela própria seed é reescrita com aviso; versão que não é da seed (v2 de import manual, ou v1 editada) nunca é tocada — só um aviso, porque sobrescrever apagaria curadoria que não está no repositório. Fora de dev/test, exceção. Coberto por `spec/db/seeds_helpers_spec.rb`. |
| `retire_rule!` | **CORRIGIDA (helper)** | Reescrevia o `title` da regra publicada (`"[REMOVIDA] … — motivo"`) e usava `Date.current` como `effective_until` — a vigência dependia do dia em que a seed rodou. Agora recebe `on:` (data da decisão: 30/08/2026 para as removidas na revisão anterior, 09/09/2026 para as desta) e preserva título e corpo; o motivo vai para o `stdout` da seed e para este documento. Regras já retiradas no banco de dev mantêm o título antigo até um `db:reset`. |
| Doc × motor na ausência de campo | **DOC CORRIGIDA** | `DSL_RULES.md` §2 dizia que só `eq`/`neq` **contra `null`** e `in` **com `null`** toleram campo ausente; no motor (`dsl/condition.rb:35-40`) `eq` devolve `false`, `neq` devolve `true` e `in` devolve `false` sobre campo ausente, sem erro — comportamento do qual regras deste diff dependem (`ICMS.ST.WITHHELD_FIELDS` usa `eq(final_consumer, false)` sem `present`). Alinhada a doc; o motor não mudou (mexer nele mexeria nas 94 regras). |
