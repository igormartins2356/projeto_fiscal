# Catálogo de regras

> Gerado a partir do banco em 2026-09-09. 94 regras ativas, 259 casos de teste. Regenerar ao alterar as seeds.

## CEST

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `CEST.FORMAT` | 1 | item | warning | 2018-01-01 → … | CEST com formato inválido |
| `CEST.MISMATCH` | 1 | item | error | 2018-01-01 → … | CEST informado não corresponde ao NCM |
| `CEST.REQUIRED` | 1 | item | error | 2018-01-01 → … | CEST ausente em NCM sujeito a ST |

## CFOP

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `CFOP.KNOWN` | 1 | item | warning | 2010-01-01 → … | CFOP fora da tabela vigente |
| `CFOP.OWN_PRODUCTION.INDUSTRY` | 1 | item | warning | 2010-01-01 → … | CFOP de produção própria em cliente sem atividade industrial |
| `CFOP.RETURN.PURPOSE` | 1 | document | error | 2010-01-01 → … | CFOP de devolução sem finalidade de devolução (ou vice-versa) |
| `CFOP.SCOPE.MATCH` | 1 | item | error | 2010-01-01 → … | CFOP × âmbito da operação (idDest) |
| `CFOP.ST.NONE_WITH_ST_CST` | 1 | item | error | 2010-01-01 → … | CFOP sem ST com CST/CSOSN de ST |
| `CFOP.ST.SUBSTITUTED_CST` | 1 | item | error | 2010-01-01 → … | CFOP de mercadoria com ST já retida exige CST 60 / CSOSN 500 |
| `CFOP.ST.SUBSTITUTE_CST` | 1 | item | error | 2010-01-01 → … | CFOP com retenção de ST exige CST/CSOSN de substituto |

## DIFAL

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `DIFAL.CALC` | 1 | item | warning | 2019-01-01 → … | Valor do DIFAL ≠ base × (alíquota interna destino − interestadual) |
| `DIFAL.INTERSTATE_RATE` | 1 | item | error | 2016-01-01 → … | Alíquota interestadual do DIFAL diverge da tabela |
| `DIFAL.REQUIRED` | 1 | item | error | 2016-01-01 → … | DIFAL ausente em venda interestadual a não contribuinte |
| `DIFAL.SIMPLES` | 1 | item | info | 2016-02-17 → … | Optante do Simples destacando DIFAL (ICMSUFDest) |

## DOC

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `DOC.COMPLEMENTARY.REFERENCE` | 1 | document | warning | 2010-01-01 → … | Nota complementar sem nota referenciada |
| `DOC.CONSUMER.TAX_TRANSPARENCY` | 1 | document | warning | 2013-06-10 → … | Venda a consumidor final sem valor aproximado dos tributos (Lei 12.741) |
| `DOC.DUPLICATE.NUMBER_SERIES` | 1 | cross_document | error | 2010-01-01 → … | Mesmo número/série autorizado com chaves diferentes |
| `DOC.EVENT.CONSISTENCY` | 1 | cross_document | warning | 2010-01-01 → … | Eventos incoerentes (cancelamento tardio, CC-e em cancelada, devolução de cancelada) |
| `DOC.ISSUER.IE_SCENARIO` | 1 | document | warning | 2010-01-01 → … | Emitente sem IE, mas cenário diz contribuinte de ICMS |
| `DOC.ISSUER.UF_SCENARIO` | 1 | document | warning | 2010-01-01 → … | UF do emitente diferente da UF do cenário |
| `DOC.ITEM.DISCOUNT_OVER_PRODUCT` | 1 | item | error | 2010-01-01 → … | Desconto maior que o valor do produto |
| `DOC.NFCE.IDENTIFY_CONSUMER` | 1 | document | warning | 2017-01-01 → … | NFC-e de valor alto sem identificação do consumidor |
| `DOC.NUMBERING.GAP` | 1 | cross_document | warning | 2010-01-01 → … | Lacuna de numeração sem inutilização |
| `DOC.NUMBERING.ORDER` | 1 | cross_document | warning | 2010-01-01 → … | Numeração fora da ordem cronológica |
| `DOC.RETURN.CFOP_REQUIRES_REFERENCE` | 1 | document | error | 2010-01-01 → … | CFOP de devolução sem nota referenciada |
| `DOC.RETURN.EXCEEDS_ORIGINAL` | 1 | cross_document | error | 2010-01-01 → … | Quantidade devolvida (acumulada) maior que a vendida |
| `DOC.RETURN.MIRROR` | 1 | cross_document | error | 2010-01-01 → … | Devolução de venda não espelha a tributação/CFOP da nota original |
| `DOC.RETURN.ORIGINAL_MISSING` | 1 | cross_document | warning | 2010-01-01 → … | Devolução de venda referencia nota do próprio cliente que não está na base |
| `DOC.RETURN.REFERENCE` | 1 | document | warning | 2010-01-01 → … | Devolução sem nota referenciada |
| `DOC.SIMPLES.CREDIT_TEXT` | 1 | document | warning | 2010-01-01 → … | CSOSN 101/201 (permite crédito) sem a expressão do art. 60 da Res. CGSN 140 |
| `DOC.SIMPLES.INFO_TEXT` | 1 | document | warning | 2010-01-01 → … | Simples Nacional sem a informação obrigatória em Informações Complementares |
| `DOC.TOTALS.ITEMS_SUM` | 1 | document | warning | 2010-01-01 → … | Totais da nota × soma dos itens |

## IBSCBS

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `IBSCBS.BASE.OPERATION_VALUE` | 1 | item | warning | 2026-01-01 → … | Base de IBS/CBS fora do intervalo do valor da operação |
| `IBSCBS.CBS.AMOUNT_CALC` | 1 | item | error | 2026-01-01 → … | vCBS ≠ base × alíquota efetiva |
| `IBSCBS.CBS.RATE_SCHEDULE` | 1 | item | error | 2026-01-01 → 2026-12-31 | Alíquota CBS × cronograma do ano (alíquota-teste de 2026) |
| `IBSCBS.CBS.RATE_SCHEDULE` | 2 | item | warning | 2027-01-01 → … | Alíquota CBS × cronograma do ano (estimativa a partir de 2027) |
| `IBSCBS.CLASS_CODE.FORMAT` | 1 | item | error | 2026-01-01 → … | cClassTrib com formato inválido |
| `IBSCBS.CST.REDUCTION_FIELDS` | 1 | item | error | 2026-01-01 → … | CST de redução (2xx) sem percentual de redução |
| `IBSCBS.CST000.WITH_REDUCTION` | 1 | item | error | 2026-01-01 → … | CST 000 (tributação integral) com redução de alíquota |
| `IBSCBS.CST_CLASS.COHERENT` | 1 | item | error | 2026-01-01 → … | CST IBS/CBS × cClassTrib |
| `IBSCBS.GROUP.REQUIRED` | 1 | item | error | 2026-01-01 → 2026-08-02 | Grupo IBS/CBS ausente (obrigatório desde 01/01/2026; SEFAZ só rejeita desde 03/08/2026) |
| `IBSCBS.GROUP.REQUIRED` | 2 | item | warning | 2026-08-03 → … | Grupo IBS/CBS ausente |
| `IBSCBS.IBS.RATE_SCHEDULE` | 1 | item | error | 2026-01-01 → … | Alíquota IBS (UF) × cronograma do ano |

## ICMS

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `ICMS.AMOUNT.CALC` | 1 | item | warning | 2010-01-01 → … | vICMS ≠ vBC × alíquota |
| `ICMS.BASE.CALC` | 1 | item | error | 2010-01-01 → … | Base de cálculo do ICMS × valor da operação |
| `ICMS.CRT.SCENARIO` | 1 | document | warning | 2010-01-01 → … | CRT da nota × regime do cenário |
| `ICMS.CST00.WITH_REDUCTION` | 1 | item | warning | 2010-01-01 → … | CST 00 com redução de base |
| `ICMS.CST51.DEFERRAL_FIELDS` | 1 | item | warning | 2016-01-01 → … | CST 51 (diferimento) sem percentual/valor diferido |
| `ICMS.EXEMPT.HIGHLIGHT` | 1 | item | warning | 2010-01-01 → … | CST de isenção/não incidência/suspensão com ICMS destacado |
| `ICMS.FCP.EXPECTED` | 1 | item | warning | 2016-01-01 → … | FCP não destacado em UF com adicional |
| `ICMS.RATE.INTERNAL` | 1 | item | warning | 2010-01-01 → … | Alíquota interna de ICMS × tabela da UF |
| `ICMS.RATE.INTERSTATE` | 1 | item | error | 2013-01-01 → … | Alíquota interestadual de ICMS |
| `ICMS.REDUCED_BASE.PCT_REQUIRED` | 1 | item | warning | 2010-01-01 → … | CST de redução de base sem percentual de redução |
| `ICMS.REGIME.SITUATION_FIELD` | 1 | item | error | 2010-01-01 → … | CST × CSOSN coerente com o regime do cenário |
| `ICMS.SIMPLES.CREDIT_CALC` | 1 | item | warning | 2010-01-01 → … | Valor do crédito do Simples ≠ valor × pCredSN |
| `ICMS.SIMPLES.CREDIT_RATE` | 1 | item | warning | 2010-01-01 → … | Alíquota de crédito do Simples (pCredSN) fora da faixa |
| `ICMS.SIMPLES.CREDIT_TO_NON_TAXPAYER` | 1 | item | error | 2010-01-01 → … | CSOSN 101/201 (com crédito) para não contribuinte |
| `ICMS.SIMPLES.NO_HIGHLIGHT` | 1 | item | warning | 2010-01-01 → … | Simples Nacional destacando ICMS próprio |
| `ICMS.ST.AMOUNT_CALC` | 1 | item | error | 2010-01-01 → … | vICMSST ≠ base ST × alíquota − ICMS próprio |
| `ICMS.ST.BASE_MVA` | 1 | item | warning | 2010-01-01 → … | Base da ST ≠ (valor + IPI) × (1 + MVA) |
| `ICMS.ST.CATALOG` | 1 | item | warning | 2010-01-01 → … | ST destacada/retida em NCM sem ST na UF (ou ausente quando devida) |
| `ICMS.ST.WITHHELD_FIELDS` | 1 | item | warning | 2018-01-01 → … | CST 60 / CSOSN 500 sem valores da ST retida anteriormente |

## IPI

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `IPI.AMOUNT.CALC` | 1 | item | error | 2010-01-01 → … | vIPI ≠ base × alíquota |
| `IPI.CST.DIRECTION` | 1 | item | error | 2010-01-01 → … | CST de IPI de entrada em nota de saída (ou vice-versa) |
| `IPI.NON_TAXPAYER.HIGHLIGHT` | 1 | item | warning | 2010-01-01 → … | IPI destacado por não contribuinte de IPI |
| `IPI.RATE.TIPI` | 1 | item | error | 2010-01-01 → … | Alíquota de IPI × TIPI |
| `IPI.SIMPLES.HIGHLIGHT` | 1 | item | error | 2010-01-01 → … | Optante do Simples destacando IPI |

## NCM

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `NCM.FORMAT` | 1 | item | warning | 2010-01-01 → … | NCM com formato inválido |
| `NCM.GENERIC.GOODS` | 1 | item | error | 2010-01-01 → … | NCM genérico (00) em item de mercadoria |
| `NCM.VALID` | 1 | item | error | 2010-01-01 → … | NCM inexistente na tabela vigente |

## NFCE

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `NFCE.CFOP.INTRASTATE` | 1 | item | error | 2013-01-01 → … | NFC-e com CFOP fora de 5xxx |
| `NFCE.RECIPIENT.NON_TAXPAYER` | 1 | document | warning | 2013-01-01 → … | NFC-e para contribuinte de ICMS |

## PISCOFINS

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `PISCOFINS.AMOUNT.CALC` | 1 | item | error | 2010-01-01 → 2026-12-31 | vPIS/vCOFINS ≠ base × alíquota |
| `PISCOFINS.CST.DIRECTION` | 1 | item | error | 2010-01-01 → 2026-12-31 | CST de PIS/COFINS de entrada em nota de saída (ou vice-versa) |
| `PISCOFINS.CST.MATCH` | 1 | item | warning | 2010-01-01 → 2026-12-31 | CST de PIS diferente do CST de COFINS |
| `PISCOFINS.CST.REGIME` | 1 | item | error | 2010-01-01 → 2026-12-31 | CST de PIS/COFINS × regime |
| `PISCOFINS.RATE.REGIME` | 1 | item | error | 2010-01-01 → 2026-12-31 | Alíquotas de PIS/COFINS × regime cumulativo/não cumulativo |
| `PISCOFINS.SIMPLES.HIGHLIGHT` | 1 | item | error | 2010-01-01 → 2026-12-31 | Optante do Simples destacando PIS/COFINS |
| `PISCOFINS.SINGLE_PHASE` | 1 | item | error | 2010-01-01 → 2026-12-31 | NCM monofásico sem CST 04 na saída |

## SCENARIO

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `SCENARIO.EXPORTS.DISAGREEMENT` | 1 | scenario | info | 2010-01-01 → … | Cenário sem exportação, mas há CFOP 7xxx |
| `SCENARIO.FINAL_CONSUMER.DISAGREEMENT` | 1 | scenario | warning | 2010-01-01 → … | Cenário sem consumidor final, mas as notas são a consumidor final |
| `SCENARIO.IPI.DISAGREEMENT` | 1 | scenario | warning | 2010-01-01 → … | Cenário sem IPI, mas as notas destacam IPI |
| `SCENARIO.NFCE.DISAGREEMENT` | 1 | scenario | warning | 2010-01-01 → … | Cenário sem NFC-e, mas o cliente emite NFC-e |
| `SCENARIO.REGIME.NORMAL_VS_SIMPLES` | 1 | scenario | warning | 2010-01-01 → … | Cenário Lucro Presumido, mas as notas declaram Simples (CRT 1) |
| `SCENARIO.REGIME.REAL_VS_SIMPLES` | 1 | scenario | warning | 2010-01-01 → … | Cenário Lucro Real, mas as notas declaram Simples (CRT 1) |
| `SCENARIO.REGIME.SIMPLES_VS_NORMAL` | 1 | scenario | warning | 2010-01-01 → … | Cenário Simples, mas as notas declaram regime normal (CRT 3) |
| `SCENARIO.ST.DISAGREEMENT` | 1 | scenario | warning | 2010-01-01 → … | Cenário sem ST, mas as notas destacam ST |

## SPED

| Código | v | Escopo | Severidade | Vigência | Título |
|---|---|---|---|---|---|
| `SPED.C190.CONSISTENCY` | 1 | period | error | 2012-01-01 → … | Registro analítico C190 não consolida os itens |
| `SPED.DOC.CANCELLED_SIT` | 1 | period | error | 2012-01-01 → … | Nota cancelada escriturada com situação errada (COD_SIT) |
| `SPED.DOC.MISSING_IN_FILE` | 1 | period | error | 2012-01-01 → … | NF-e autorizada fora da EFD (ou C100 sem XML na base) |
| `SPED.DOC.NO_ANALYTIC` | 1 | period | error | 2012-01-01 → … | C100 regular sem registro analítico C190 |
| `SPED.DOC.VALUES` | 1 | period | error | 2012-01-01 → … | Totais do C100 divergem do XML |
| `SPED.ITEM.MISMATCH` | 1 | period | error | 2012-01-01 → … | Item do C170 diverge do item do XML |
| `SPED.STRUCTURE` | 1 | period | warning | 2012-01-01 → … | Erros estruturais do arquivo (leiaute) |
