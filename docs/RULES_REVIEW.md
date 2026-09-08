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
