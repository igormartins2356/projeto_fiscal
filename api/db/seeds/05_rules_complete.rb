load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true) && respond_to?(:seed_rule!, true)
# Base completa de regras (curadoria 30/08/2026). Todas são dado; código só avalia. Convenções: guardar todo campo com `present`
# antes de comparar; severidade error = está errado; warning = provavelmente errado; info = atenção.
issuer = { "field" => "doc.role", "op" => "eq", "value" => "issuer" }
outbound = { "field" => "doc.operation.direction", "op" => "eq", "value" => "outbound" }
goods = { "field" => "item.is_service", "op" => "eq", "value" => false }
simples = { "field" => "scenario.tax_regime", "op" => "in", "value" => %w[simples_nacional simples_nacional_excess mei] }
normal_regime = { "field" => "scenario.tax_regime", "op" => "in", "value" => %w[lucro_presumido lucro_real] }
authorized = { "field" => "doc.status.state", "op" => "eq", "value" => "authorized" }
def present(f) = { "field" => f, "op" => "present" }
def eq(f, v) = { "field" => f, "op" => "eq", "value" => v }
def inn(f, v) = { "field" => f, "op" => "in", "value" => v }
def gt(f, v) = { "field" => f, "op" => "gt", "value" => v }
def approx(f, ref, tol = "0.02") = { "field" => f, "op" => "approx", "value" => { "ref" => ref }, "tolerance" => tol }
old = Date.new(2010, 1, 1)

# ------------------------------------------------------------------ Documento
seed_rule!("DOC.SIMPLES.INFO_TEXT", title: "Simples Nacional sem a informação obrigatória em Informações Complementares", scope: "document", severity: "warning", effective_from: old, tags: %w[simples_nacional document],
  applies_when: { "all" => [issuer, simples, eq("doc.model", "55")] },
  assert: { "any" => [{ "all" => [present("doc.additional_info.complementary"), { "field" => "doc.additional_info.complementary", "op" => "regex", "value" => "(?i)SIMPLES\\s+NACIONAL" }] },
                      { "all" => [present("doc.additional_info.tax_authority"), { "field" => "doc.additional_info.tax_authority", "op" => "regex", "value" => "(?i)SIMPLES\\s+NACIONAL" }] }] },
  message: "Nota de optante do Simples sem a frase \"Documento emitido por ME ou EPP optante pelo Simples Nacional…\" nas informações complementares.",
  legal_references: [{ "label" => "Resolução CGSN 140/2018, art. 59" }])

seed_rule!("DOC.CONSUMER.TAX_TRANSPARENCY", title: "Venda a consumidor final sem valor aproximado dos tributos (Lei 12.741)", scope: "document", severity: "warning", effective_from: Date.new(2013, 6, 10), tags: %w[document consumer],
  applies_when: { "all" => [issuer, outbound, eq("doc.operation.final_consumer", true), eq("doc.operation.nature", "sale")] },
  assert: { "all" => [present("doc.totals.approx_taxes"), gt("doc.totals.approx_taxes", 0)] },
  message: "Venda a consumidor final sem vTotTrib (valor aproximado dos tributos), exigido pela Lei 12.741/2012.",
  legal_references: [{ "label" => "Lei 12.741/2012" }])

seed_rule!("DOC.NFCE.IDENTIFY_CONSUMER", title: "NFC-e de valor alto sem identificação do consumidor", scope: "document", severity: "warning", effective_from: Date.new(2017, 1, 1), tags: %w[nfce],
  params: { "limit" => "10000" },
  applies_when: { "all" => [issuer, eq("doc.model", "65"), present("doc.totals.total")] },
  assert: { "any" => [{ "field" => "doc.totals.total", "op" => "lt", "value" => { "param" => "limit" } }, present("doc.recipient.cpf"), present("doc.recipient.cnpj"), present("doc.recipient.foreign_id")] },
  message: "NFC-e de R$ {{doc.totals.total}} sem identificação do consumidor (CPF/CNPJ); obrigatória a partir de R$ {{params.limit}}.",
  legal_references: [{ "label" => "Ajuste SINIEF 07/05 (Ajuste SINIEF 19/16)" }])

seed_rule!("DOC.COMPLEMENTARY.REFERENCE", title: "Nota complementar sem nota referenciada", scope: "document", severity: "error", effective_from: old, tags: %w[document],
  applies_when: { "all" => [issuer, eq("doc.issuance.purpose", "complementary")] },
  assert: { "some" => "doc.references", "as" => "r", "where" => present("r.access_key") },
  message: "Nota complementar (finNFe=2) sem referência à nota original.")

seed_rule!("DOC.ISSUER.UF_SCENARIO", title: "UF do emitente diferente da UF do cenário", scope: "document", severity: "warning", effective_from: old, tags: %w[scenario],
  applies_when: { "all" => [issuer, present("doc.issuer.uf"), present("scenario.uf")] },
  assert: eq("doc.issuer.uf", { "ref" => "scenario.uf" }),
  message: "Nota emitida com UF {{doc.issuer.uf}}, mas o cenário do cliente é {{scenario.uf}}. Filial em outra UF? Cadastre como outro cliente.")

seed_rule!("DOC.ISSUER.IE_SCENARIO", title: "Emitente sem IE, mas cenário diz contribuinte de ICMS", scope: "document", severity: "warning", effective_from: old, tags: %w[scenario icms],
  applies_when: { "all" => [issuer, eq("scenario.icms_taxpayer", true)] },
  assert: present("doc.issuer.ie"),
  message: "A nota não traz IE do emitente, mas o cenário indica contribuinte de ICMS.")

seed_rule!("DOC.RETURN.CFOP_REQUIRES_REFERENCE", title: "CFOP de devolução sem nota referenciada", scope: "document", severity: "error", effective_from: old, tags: %w[return cfop],
  applies_when: { "all" => [issuer, { "some" => "doc.items", "as" => "i", "where" => eq("i.cfop_requires_reference", true) }] },
  assert: { "some" => "doc.references", "as" => "r", "where" => { "any" => [present("r.access_key"), present("r.nf_model_1")] } },
  message: "Itens com CFOP de devolução ({{doc.operation.cfops}}) exigem a nota de origem em NFref.")

seed_rule!("DOC.ITEM.DISCOUNT_OVER_PRODUCT", title: "Desconto maior que o valor do produto", scope: "item", severity: "error", effective_from: old, tags: %w[integrity],
  applies_when: { "all" => [present("item.product.discount"), present("item.product.gross_amount")] },
  assert: { "field" => "item.product.discount", "op" => "lte", "value" => { "ref" => "item.product.gross_amount" } },
  message: "Desconto {{item.product.discount}} maior que o valor bruto {{item.product.gross_amount}} do item.")

# ------------------------------------------------------------------ CFOP × CST (ST)
with_st_kinds = %w[taxed_with_st exempt_with_st reduced_base_with_st simples_with_credit_st simples_without_credit_st exempt_st other]
seed_rule!("CFOP.ST.SUBSTITUTED_CST", title: "CFOP de mercadoria com ST já retida exige CST 60 / CSOSN 500", scope: "item", severity: "error", effective_from: old, tags: %w[cfop st icms],
  applies_when: { "all" => [issuer, goods, eq("item.cfop_st_role", "substituted"), present("item.icms.taxation_kind")] },
  assert: eq("item.icms.taxation_kind", "st_withheld"),
  message: "CFOP {{item.product.cfop}} (mercadoria com ST já retida) com CST/CSOSN {{item.icms.situation_code}}; esperado CST 60 ou CSOSN 500.",
  group_by: ["item.product.cfop", "item.icms.situation_code"])

seed_rule!("CFOP.ST.SUBSTITUTE_CST", title: "CFOP com retenção de ST exige CST/CSOSN de substituto", scope: "item", severity: "error", effective_from: old, tags: %w[cfop st icms],
  applies_when: { "all" => [issuer, goods, outbound, eq("item.cfop_st_role", "substitute"), present("item.icms.taxation_kind")] },
  assert: inn("item.icms.taxation_kind", with_st_kinds),
  message: "CFOP {{item.product.cfop}} (venda com retenção de ST) com CST/CSOSN {{item.icms.situation_code}}; esperado 10/30/70/90 ou CSOSN 201/202/203/900.",
  group_by: ["item.product.cfop", "item.icms.situation_code"])

seed_rule!("CFOP.ST.NONE_WITH_ST_CST", title: "CFOP sem ST com CST/CSOSN de ST", scope: "item", severity: "error", effective_from: old, tags: %w[cfop st icms],
  applies_when: { "all" => [issuer, goods, outbound, eq("item.cfop_st_role", "none"), inn("item.cfop_nature", %w[sale transfer bonus]), present("item.icms.taxation_kind")] },
  assert: { "field" => "item.icms.taxation_kind", "op" => "not_in", "value" => %w[st_withheld taxed_with_st simples_with_credit_st simples_without_credit_st exempt_st reduced_base_with_st exempt_with_st] },
  message: "CFOP {{item.product.cfop}} não é de ST, mas o item usa CST/CSOSN {{item.icms.situation_code}}. Use 5405/6404 (ST retida) ou 5401/5403 (substituto).",
  group_by: ["item.product.cfop", "item.icms.situation_code"])

seed_rule!("CFOP.OWN_PRODUCTION.INDUSTRY", title: "CFOP de produção própria em cliente sem atividade industrial", scope: "item", severity: "warning", effective_from: old, tags: %w[cfop scenario],
  applies_when: { "all" => [issuer, eq("item.cfop_own_production", true), present("scenario.activity")] },
  assert: { "any" => [{ "field" => "scenario.activity", "op" => "contains", "value" => "industry" }, { "field" => "scenario.activity", "op" => "contains", "value" => "rural" }] },
  message: "CFOP {{item.product.cfop}} (produção do estabelecimento), mas o cenário não inclui indústria nem produção rural. Revise o CFOP (5102?) ou o cenário.",
  group_by: ["item.product.cfop"])

# ------------------------------------------------------------------ ICMS
seed_rule!("ICMS.RATE.INTERNAL", title: "Alíquota interna de ICMS × tabela da UF", scope: "item", severity: "error", effective_from: old, tags: %w[icms],
  let: [{ "lookup" => "icms_internal_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, { "ref" => "item.product.ncm" }], "as" => "by_ncm" },
        { "lookup" => "icms_internal_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, "*"], "as" => "general" }],
  applies_when: { "all" => [issuer, normal_regime, goods, eq("doc.operation.scope", "intrastate"), inn("item.icms.taxation_kind", %w[taxed taxed_with_st]), present("item.icms.rate"),
                            { "any" => [present("by_ncm"), present("general")] }, { "field" => "item.icms.base_reduction_pct", "op" => "absent" }] },
  assert: { "if" => present("by_ncm"), "then" => approx("item.icms.rate", "by_ncm.rate", "0.001"), "else" => approx("item.icms.rate", "general.rate", "0.001") },
  message: "Alíquota interna {{item.icms.rate}}% em {{doc.operation.origin_uf}} para NCM {{item.product.ncm}}; tabela indica {{by_ncm.rate}}{{general.rate}}%.",
  group_by: ["item.icms.rate", "item.product.ncm"])

seed_rule!("ICMS.EXEMPT.HIGHLIGHT", title: "CST de isenção/não incidência/suspensão com ICMS destacado", scope: "item", severity: "error", effective_from: old, tags: %w[icms],
  applies_when: { "all" => [issuer, inn("item.icms.taxation_kind", %w[exempt not_taxed suspended immune st_withheld]), present("item.icms.amount")] },
  assert: { "field" => "item.icms.amount", "op" => "lte", "value" => 0 },
  message: "CST/CSOSN {{item.icms.situation_code}} ({{item.icms.taxation_kind}}) com vICMS {{item.icms.amount}}: não pode haver destaque de ICMS próprio.",
  group_by: ["item.icms.situation_code"])

seed_rule!("ICMS.REDUCED_BASE.PCT_REQUIRED", title: "CST de redução de base sem percentual de redução", scope: "item", severity: "error", effective_from: old, tags: %w[icms],
  applies_when: { "all" => [issuer, inn("item.icms.cst", %w[20 70])] },
  assert: { "all" => [present("item.icms.base_reduction_pct"), gt("item.icms.base_reduction_pct", 0)] },
  message: "CST {{item.icms.cst}} (redução de base) sem pRedBC informado.")

seed_rule!("ICMS.CST00.WITH_REDUCTION", title: "CST 00 com redução de base", scope: "item", severity: "error", effective_from: old, tags: %w[icms],
  applies_when: { "all" => [issuer, eq("item.icms.cst", "00"), present("item.icms.base_reduction_pct")] },
  assert: { "field" => "item.icms.base_reduction_pct", "op" => "lte", "value" => 0 },
  message: "CST 00 (tributada integralmente) com pRedBC {{item.icms.base_reduction_pct}}%; use CST 20.")

seed_rule!("ICMS.CST51.DEFERRAL_FIELDS", title: "CST 51 (diferimento) sem percentual/valor diferido", scope: "item", severity: "warning", effective_from: Date.new(2016, 1, 1), tags: %w[icms],
  applies_when: { "all" => [issuer, eq("item.icms.cst", "51")] },
  assert: { "any" => [present("item.icms.deferral.pct"), present("item.icms.deferral.deferred_amount")] },
  message: "CST 51 sem pDif/vICMSDif: informe o percentual e o valor do ICMS diferido.")

seed_rule!("ICMS.FCP.EXPECTED", title: "FCP não destacado em UF com adicional", scope: "item", severity: "warning", effective_from: Date.new(2016, 1, 1), tags: %w[icms fcp],
  let: [{ "lookup" => "icms_internal_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, "*"], "as" => "general" }],
  applies_when: { "all" => [issuer, normal_regime, goods, eq("doc.operation.scope", "intrastate"), inn("item.icms.taxation_kind", %w[taxed reduced_base]), present("general.fcp_rate"), gt("general.fcp_rate", 0), gt("item.icms.amount", 0)] },
  assert: { "all" => [present("item.icms.fcp.rate"), gt("item.icms.fcp.rate", 0)] },
  message: "UF {{doc.operation.origin_uf}} tem FCP de {{general.fcp_rate}}% e o item não destaca FCP (pode ser correto se o NCM estiver fora do adicional).",
  group_by: ["item.product.ncm"])

seed_rule!("ICMS.SIMPLES.CREDIT_RATE", title: "Alíquota de crédito do Simples (pCredSN) fora da faixa", scope: "item", severity: "warning", effective_from: old, tags: %w[icms simples_nacional],
  applies_when: { "all" => [issuer, simples, inn("item.icms.csosn", %w[101 201 900]), present("item.icms.simples_credit.rate")] },
  assert: { "field" => "item.icms.simples_credit.rate", "op" => "between", "value" => ["1.25", "3.95"] },
  message: "pCredSN {{item.icms.simples_credit.rate}}% fora da faixa do Simples Nacional (1,25% a 3,95%).",
  legal_references: [{ "label" => "LC 123/2006, art. 23" }])

seed_rule!("ICMS.SIMPLES.CREDIT_CALC", title: "Valor do crédito do Simples ≠ valor × pCredSN", scope: "item", severity: "warning", effective_from: old, tags: %w[icms simples_nacional],
  let: [{ "calc" => "round(item.net_amount * item.icms.simples_credit.rate / 100, 2)", "as" => "expected_credit" }, { "calc" => "round(item.product.gross_amount * item.icms.simples_credit.rate / 100, 2)", "as" => "expected_credit_gross" }],
  applies_when: { "all" => [issuer, simples, present("item.icms.simples_credit.rate"), present("item.icms.simples_credit.amount"), present("item.net_amount")] },
  assert: { "any" => [approx("item.icms.simples_credit.amount", "expected_credit", "0.05"), approx("item.icms.simples_credit.amount", "expected_credit_gross", "0.05")] },
  message: "vCredICMSSN {{item.icms.simples_credit.amount}} difere de valor × {{item.icms.simples_credit.rate}}% (≈ {{expected_credit}}).",
  legal_references: [{ "label" => "LC 123/2006 art. 23; Res. CGSN 140/2018 art. 60" }])

seed_rule!("DOC.SIMPLES.CREDIT_TEXT", title: "CSOSN 101/201 (permite crédito) sem a expressão do art. 60 da Res. CGSN 140", scope: "document", severity: "warning", effective_from: old, tags: %w[simples_nacional document],
  applies_when: { "all" => [issuer, simples, { "some" => "doc.items", "as" => "i", "where" => inn("i.icms.csosn", %w[101 201]) }] },
  assert: { "any" => [{ "all" => [present("doc.additional_info.complementary"), { "field" => "doc.additional_info.complementary", "op" => "regex", "value" => "(?i)PERMITE\\s+O\\s+APROVEITAMENTO\\s+DO\\s+CR[EÉ]DITO" }] },
                      { "all" => [present("doc.additional_info.tax_authority"), { "field" => "doc.additional_info.tax_authority", "op" => "regex", "value" => "(?i)PERMITE\\s+O\\s+APROVEITAMENTO\\s+DO\\s+CR[EÉ]DITO" }] }] },
  message: "Nota com CSOSN 101/201 sem a expressão \"PERMITE O APROVEITAMENTO DO CRÉDITO DE ICMS NO VALOR DE R$…; CORRESPONDENTE À ALÍQUOTA DE …%\" nas informações complementares.",
  legal_references: [{ "label" => "Resolução CGSN 140/2018, art. 60" }])

seed_rule!("ICMS.SIMPLES.CREDIT_TO_NON_TAXPAYER", title: "CSOSN 101/201 (com crédito) para não contribuinte", scope: "item", severity: "error", effective_from: old, tags: %w[icms simples_nacional],
  applies_when: { "all" => [issuer, simples, inn("item.icms.csosn", %w[101 201]), present("doc.recipient.ie_indicator")] },
  assert: eq("doc.recipient.ie_indicator", "taxpayer"),
  message: "CSOSN {{item.icms.csosn}} permite crédito ao adquirente, mas o destinatário não é contribuinte (indIEDest {{doc.recipient.ie_indicator}}); use 102/202.")

seed_rule!("ICMS.ST.BASE_MVA", title: "Base da ST ≠ (valor + IPI) × (1 + MVA)", scope: "item", severity: "warning", effective_from: old, tags: %w[icms st],
  params: { "tolerance_pct" => "0.5" },
  applies_when: { "all" => [issuer, present("item.icms_st.expected_base_amount"), present("item.icms_st.base_amount"), gt("item.icms_st.base_amount", 0)] },
  assert: { "field" => "item.icms_st.base_amount", "op" => "approx", "value" => { "ref" => "item.icms_st.expected_base_amount" }, "tolerance_pct" => { "param" => "tolerance_pct" } },
  message: "Base da ST {{item.icms_st.base_amount}} difere de (valor + IPI) × (1 + MVA {{item.icms_st.mva_pct}}%) = {{item.icms_st.expected_base_amount}}. Frete/desconto não considerados?")

seed_rule!("ICMS.ST.AMOUNT_CALC", title: "vICMSST ≠ base ST × alíquota − ICMS próprio", scope: "item", severity: "error", effective_from: old, tags: %w[icms st],
  params: { "tolerance" => "0.05" },
  applies_when: { "all" => [issuer, present("item.icms_st.expected_amount"), present("item.icms_st.amount")] },
  assert: { "field" => "item.icms_st.amount", "op" => "approx", "value" => { "ref" => "item.icms_st.expected_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "ICMS-ST {{item.icms_st.amount}} difere de {{item.icms_st.base_amount}} × {{item.icms_st.rate}}% − ICMS próprio = {{item.icms_st.expected_amount}}.")

seed_rule!("ICMS.ST.WITHHELD_FIELDS", title: "CST 60 / CSOSN 500 sem valores da ST retida anteriormente", scope: "item", severity: "warning", effective_from: Date.new(2018, 1, 1), tags: %w[icms st],
  applies_when: { "all" => [issuer, outbound, eq("item.icms.taxation_kind", "st_withheld"), inn("doc.recipient.ie_indicator", %w[taxpayer])] },
  assert: present("item.icms_st.withheld.amount"),
  message: "CST 60/CSOSN 500 sem vBCSTRet/vICMSSTRet: informe a base e o ICMS retido anteriormente (exigido nas saídas a contribuinte).",
  legal_references: [{ "label" => "NT 2018.005" }])

seed_rule!("DIFAL.CALC", title: "Valor do DIFAL ≠ base × (alíquota interna destino − interestadual)", scope: "item", severity: "warning", effective_from: Date.new(2019, 1, 1), tags: %w[icms difal],
  explanation: "Fórmula de base única. UFs com base dupla (ex.: MG, PR, RS, SE…) calculam por dentro e o valor diverge — nesses casos confira antes de corrigir.",
  params: { "tolerance" => "0.05" },
  applies_when: { "all" => [issuer, present("item.icms_uf_dest.expected_destination_amount"), present("item.icms_uf_dest.destination_amount")] },
  assert: { "field" => "item.icms_uf_dest.destination_amount", "op" => "approx", "value" => { "ref" => "item.icms_uf_dest.expected_destination_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "DIFAL {{item.icms_uf_dest.destination_amount}} difere de {{item.icms_uf_dest.base_amount}} × ({{item.icms_uf_dest.destination_internal_rate}}% − {{item.icms_uf_dest.interstate_rate}}%) = {{item.icms_uf_dest.expected_destination_amount}}.")

seed_rule!("DIFAL.INTERSTATE_RATE", title: "Alíquota interestadual do DIFAL diverge da tabela", scope: "item", severity: "error", effective_from: Date.new(2016, 1, 1), tags: %w[icms difal],
  let: [{ "lookup" => "icms_interstate_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, { "ref" => "doc.operation.destination_uf" }, { "ref" => "item.icms.origin_category" }], "as" => "expected" }],
  applies_when: { "all" => [issuer, present("item.icms_uf_dest.interstate_rate"), present("expected")] },
  assert: approx("item.icms_uf_dest.interstate_rate", "expected.rate", "0.001"),
  message: "pICMSInter {{item.icms_uf_dest.interstate_rate}}% no grupo DIFAL; esperado {{expected.rate}}% para {{doc.operation.origin_uf}}→{{doc.operation.destination_uf}}.")

seed_rule!("DIFAL.SIMPLES", title: "Optante do Simples destacando DIFAL (ICMSUFDest)", scope: "item", severity: "info", effective_from: Date.new(2016, 2, 17), tags: %w[icms difal simples_nacional],
  applies_when: { "all" => [issuer, simples, eq("item.has_difal", true)] },
  assert: { "field" => "item.has_difal", "op" => "eq", "value" => false },
  message: "Optante do Simples com grupo ICMSUFDest: a cobrança do DIFAL do Simples está suspensa (ADI 5464/STF); confira se há recolhimento indevido.",
  legal_references: [{ "label" => "ADI 5464 (STF)" }])

seed_rule!("ICMS.IMPORTED.ORIGIN_INTERSTATE", title: "Origem importada com alíquota interestadual ≠ 4%", scope: "item", severity: "error", effective_from: Date.new(2013, 1, 1), tags: %w[icms interstate],
  applies_when: { "all" => [issuer, normal_regime, eq("doc.operation.scope", "interstate"), eq("item.icms.origin_category", "imported"), inn("item.icms.taxation_kind", %w[taxed taxed_with_st]), present("item.icms.rate")] },
  assert: approx("item.icms.rate", "item.icms.rate", "0").merge("value" => "4.00", "tolerance" => "0.001"),
  message: "Mercadoria de origem {{item.icms.origin}} (importada) em operação interestadual com alíquota {{item.icms.rate}}%; Resolução SF 13/2012 fixa 4%.",
  legal_references: [{ "label" => "Resolução Senado 13/2012" }])

# ------------------------------------------------------------------ IPI
seed_rule!("IPI.CST.DIRECTION", title: "CST de IPI de entrada em nota de saída (ou vice-versa)", scope: "item", severity: "error", effective_from: old, tags: %w[ipi],
  applies_when: { "all" => [issuer, present("item.ipi.cst_direction"), { "field" => "item.ipi.cst_direction", "op" => "neq", "value" => "unknown" }, present("doc.operation.direction_declared")] },
  assert: eq("item.ipi.cst_direction", { "ref" => "doc.operation.direction_declared" }),
  message: "CST IPI {{item.ipi.cst}} é de {{item.ipi.cst_direction}}, mas a nota é de {{doc.operation.direction_declared}} (saída usa 50–99; entrada 00–49).",
  group_by: ["item.ipi.cst"])

seed_rule!("IPI.AMOUNT.CALC", title: "vIPI ≠ base × alíquota", scope: "item", severity: "error", effective_from: old, tags: %w[ipi],
  params: { "tolerance" => "0.02" },
  applies_when: { "all" => [issuer, present("item.ipi.expected_amount"), present("item.ipi.amount")] },
  assert: { "field" => "item.ipi.amount", "op" => "approx", "value" => { "ref" => "item.ipi.expected_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "IPI {{item.ipi.amount}} difere de {{item.ipi.base_amount}} × {{item.ipi.rate}}% = {{item.ipi.expected_amount}}.")

seed_rule!("IPI.SIMPLES.HIGHLIGHT", title: "Optante do Simples destacando IPI", scope: "item", severity: "error", effective_from: old, tags: %w[ipi simples_nacional],
  applies_when: { "all" => [issuer, simples, present("item.ipi.amount")] },
  assert: { "field" => "item.ipi.amount", "op" => "lte", "value" => 0 },
  message: "Optante do Simples com IPI destacado ({{item.ipi.amount}}); o IPI está incluído no DAS (CST 99 sem valor).",
  legal_references: [{ "label" => "LC 123/2006, art. 13" }])

seed_rule!("IPI.RATE.TIPI", title: "Alíquota de IPI × TIPI", scope: "item", severity: "error", effective_from: old, tags: %w[ipi tipi],
  let: [{ "lookup" => "tipi", "key" => [{ "ref" => "item.product.ncm" }], "as" => "tipi" }],
  applies_when: { "all" => [issuer, normal_regime, eq("scenario.ipi_taxpayer", true), eq("item.ipi.taxed", true), present("item.ipi.rate"), present("tipi"), present("tipi.rate"), { "field" => "item.product.ex_tipi", "op" => "absent" }] },
  assert: approx("item.ipi.rate", "tipi.rate", "0.001"),
  message: "IPI {{item.ipi.rate}}% para NCM {{item.product.ncm}}; TIPI vigente indica {{tipi.rate}}%.",
  legal_references: [{ "label" => "Decreto 11.158/2022 (TIPI)" }], group_by: ["item.product.ncm", "item.ipi.rate"])

# ------------------------------------------------------------------ PIS/COFINS
seed_rule!("PISCOFINS.CST.DIRECTION", title: "CST de PIS/COFINS de entrada em nota de saída (ou vice-versa)", scope: "item", severity: "error", effective_from: old, effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins],
  applies_when: { "all" => [issuer, present("item.pis.cst_direction"), { "field" => "item.pis.cst_direction", "op" => "neq", "value" => "unknown" }, present("doc.operation.direction_declared")] },
  assert: eq("item.pis.cst_direction", { "ref" => "doc.operation.direction_declared" }),
  message: "PIS CST {{item.pis.cst}} é de {{item.pis.cst_direction}}, mas a nota é de {{doc.operation.direction_declared}} (saída 01–49; entrada 50–99).",
  group_by: ["item.pis.cst"])

seed_rule!("PISCOFINS.CST.MATCH", title: "CST de PIS diferente do CST de COFINS", scope: "item", severity: "warning", effective_from: old, effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins],
  applies_when: { "all" => [issuer, present("item.pis.cst"), present("item.cofins.cst")] },
  assert: eq("item.pis.cst", { "ref" => "item.cofins.cst" }),
  message: "PIS CST {{item.pis.cst}} e COFINS CST {{item.cofins.cst}} divergem; as contribuições seguem a mesma sistemática.")

seed_rule!("PISCOFINS.AMOUNT.CALC", title: "vPIS/vCOFINS ≠ base × alíquota", scope: "item", severity: "error", effective_from: old, effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins],
  params: { "tolerance" => "0.02" },
  applies_when: { "all" => [issuer, present("item.pis.expected_amount"), present("item.pis.amount"), present("item.cofins.expected_amount"), present("item.cofins.amount")] },
  assert: { "all" => [{ "field" => "item.pis.amount", "op" => "approx", "value" => { "ref" => "item.pis.expected_amount" }, "tolerance" => { "param" => "tolerance" } },
                      { "field" => "item.cofins.amount", "op" => "approx", "value" => { "ref" => "item.cofins.expected_amount" }, "tolerance" => { "param" => "tolerance" } }] },
  message: "PIS {{item.pis.amount}} (esperado {{item.pis.expected_amount}}) / COFINS {{item.cofins.amount}} (esperado {{item.cofins.expected_amount}}).")

seed_rule!("PISCOFINS.SIMPLES.HIGHLIGHT", title: "Optante do Simples destacando PIS/COFINS", scope: "item", severity: "error", effective_from: old, effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins simples_nacional],
  applies_when: { "all" => [issuer, simples, { "any" => [present("item.pis.amount"), present("item.cofins.amount")] }] },
  assert: { "all" => [{ "any" => [{ "field" => "item.pis.amount", "op" => "absent" }, { "field" => "item.pis.amount", "op" => "lte", "value" => 0 }] },
                      { "any" => [{ "field" => "item.cofins.amount", "op" => "absent" }, { "field" => "item.cofins.amount", "op" => "lte", "value" => 0 }] }] },
  message: "Optante do Simples com PIS/COFINS destacados (PIS {{item.pis.amount}}, COFINS {{item.cofins.amount}}); as contribuições estão no DAS.")

seed_rule!("PISCOFINS.SINGLE_PHASE", title: "NCM monofásico sem CST 04 na saída", scope: "item", severity: "error", effective_from: old, effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins monofasico],
  let: [{ "lookup" => "pis_cofins_special", "key" => [{ "ref" => "item.product.ncm" }], "as" => "special" }],
  applies_when: { "all" => [issuer, outbound, eq("item.cfop_nature", "sale"), present("special"), eq("special.kind", "single_phase"), present("item.pis.cst")] },
  assert: { "any" => [inn("item.pis.cst", %w[04 05 06 08]), { "all" => [{ "any" => [{ "field" => "scenario.activity", "op" => "contains", "value" => "industry" }, eq("scenario.imports", true)] }, eq("item.pis.cst", "02")] }] },
  message: "NCM {{item.product.ncm}} é monofásico de PIS/COFINS ({{special.legal_basis}}); revenda usa CST 04 (fabricante ou importador: 02 com alíquota diferenciada), encontrado {{item.pis.cst}}.",
  group_by: ["item.product.ncm", "item.pis.cst"])

# ------------------------------------------------------------------ CEST / NCM
seed_rule!("CEST.MISMATCH", title: "CEST informado não corresponde ao NCM", scope: "item", severity: "error", effective_from: Date.new(2018, 1, 1), tags: %w[cest st],
  applies_when: { "all" => [issuer, goods, present("item.product.cest"), present("item.expected_cest"), { "field" => "item.expected_cest", "op" => "not_empty" }] },
  assert: { "field" => "item.expected_cest", "op" => "contains", "value" => { "ref" => "item.product.cest" } },
  message: "CEST {{item.product.cest}} não é compatível com o NCM {{item.product.ncm}} (esperado: {{item.expected_cest}}).",
  group_by: ["item.product.ncm", "item.product.cest"])

seed_rule!("CEST.FORMAT", title: "CEST com formato inválido", scope: "item", severity: "error", effective_from: Date.new(2018, 1, 1), tags: %w[cest],
  applies_when: { "all" => [issuer, present("item.product.cest")] },
  assert: { "field" => "item.product.cest", "op" => "regex", "value" => "^\\d{7}$" },
  message: "CEST {{item.product.cest}} deve ter 7 dígitos.")

seed_rule!("NCM.FORMAT", title: "NCM com formato inválido", scope: "item", severity: "error", effective_from: old, tags: %w[ncm],
  applies_when: { "all" => [issuer, goods, present("item.product.ncm")] },
  assert: { "field" => "item.product.ncm", "op" => "regex", "value" => "^(\\d{8}|00)$" },
  message: "NCM {{item.product.ncm}} inválido: use 8 dígitos (ou 00 apenas para serviços/itens sem mercadoria).")

seed_rule!("NCM.GENERIC.GOODS", title: "NCM genérico (00) em item de mercadoria", scope: "item", severity: "error", effective_from: old, tags: %w[ncm],
  applies_when: { "all" => [issuer, goods, eq("item.ncm_generic", true), inn("item.cfop_nature", %w[sale sale_return purchase_return transfer bonus])] },
  assert: eq("item.ncm_generic", false),
  message: "Item de mercadoria (CFOP {{item.product.cfop}}) com NCM genérico; informe o NCM de 8 dígitos.")

# ------------------------------------------------------------------ IBS/CBS (reforma)
seed_rule!("IBSCBS.IBS.RATE_SCHEDULE", title: "Alíquota IBS (UF) × cronograma do ano", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, eq("item.ibs_cbs.present", true), eq("item.ibs_cbs.cst", "000"), present("item.ibs_cbs.ibs_uf.rate"), present("item.ibs_cbs.schedule_rates.ibs_uf")] },
  assert: approx("item.ibs_cbs.ibs_uf.rate", "item.ibs_cbs.schedule_rates.ibs_uf", "0.001"),
  message: "Alíquota IBS estadual {{item.ibs_cbs.ibs_uf.rate}}% diverge do cronograma ({{item.ibs_cbs.schedule_rates.ibs_uf}}%).",
  legal_references: [{ "label" => "LC 214/2025 art. 343" }])

seed_rule!("IBSCBS.CBS.AMOUNT_CALC", title: "vCBS ≠ base × alíquota efetiva", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, present("item.ibs_cbs.cbs.expected_amount"), present("item.ibs_cbs.cbs.amount")] },
  assert: approx("item.ibs_cbs.cbs.amount", "item.ibs_cbs.cbs.expected_amount", "0.02"),
  message: "CBS {{item.ibs_cbs.cbs.amount}} difere de {{item.ibs_cbs.base_amount}} × {{item.ibs_cbs.cbs.effective_rate}}% = {{item.ibs_cbs.cbs.expected_amount}}.")

seed_rule!("IBSCBS.BASE.OPERATION_VALUE", title: "Base de IBS/CBS fora do intervalo do valor da operação", scope: "item", severity: "warning", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  let: [{ "calc" => "item.net_amount - coalesce(opt(item.icms.amount), 0) - coalesce(opt(item.pis.amount), 0) - coalesce(opt(item.cofins.amount), 0) - coalesce(opt(item.ipi.amount), 0)", "as" => "lower" },
        { "calc" => "item.net_amount + coalesce(opt(item.ipi.amount), 0) * 0", "as" => "upper" }],
  applies_when: { "all" => [issuer, eq("item.ibs_cbs.present", true), present("item.ibs_cbs.base_amount"), gt("item.ibs_cbs.base_amount", 0), present("item.net_amount"), inn("item.ibs_cbs.cst", %w[000 200 210])] },
  assert: { "all" => [{ "field" => "item.ibs_cbs.base_amount", "op" => "gte", "value" => { "calc" => "lower * 0.995" } }, { "field" => "item.ibs_cbs.base_amount", "op" => "lte", "value" => { "calc" => "upper * 1.005" } }] },
  message: "Base IBS/CBS {{item.ibs_cbs.base_amount}} fora do intervalo esperado ({{lower}} a {{upper}}): valor da operação sem IPI e descontos, podendo excluir ICMS/PIS/COFINS (LC 214 art. 12 §2).",
  explanation: "Art. 12 §2 da LC 214/2025 exclui da base o próprio IBS/CBS, o IPI, descontos incondicionais e o ICMS/ISS/PIS/COFINS. Entre 'valor líquido' (limite superior) e 'valor líquido menos tributos embutidos' (inferior) qualquer base é plausível; fora disso há erro de cálculo no ERP.",
  legal_references: [{ "label" => "LC 214/2025 art. 12" }])

seed_rule!("IBSCBS.CST.REDUCTION_FIELDS", title: "CST de redução (2xx) sem percentual de redução", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, eq("item.ibs_cbs.present", true), { "field" => "item.ibs_cbs.cst", "op" => "starts_with", "value" => "2" }] },
  assert: { "any" => [present("item.ibs_cbs.cbs.reduction_pct"), present("item.ibs_cbs.ibs_uf.reduction_pct")] },
  message: "CST IBS/CBS {{item.ibs_cbs.cst}} (alíquota reduzida) sem pRedAliq informado.")

seed_rule!("IBSCBS.CST000.WITH_REDUCTION", title: "CST 000 (tributação integral) com redução de alíquota", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, eq("item.ibs_cbs.cst", "000"), present("item.ibs_cbs.cbs.reduction_pct")] },
  assert: { "field" => "item.ibs_cbs.cbs.reduction_pct", "op" => "lte", "value" => 0 },
  message: "CST 000 com pRedAliq {{item.ibs_cbs.cbs.reduction_pct}}%; use um CST 2xx com o cClassTrib da redução.")

seed_rule!("IBSCBS.CLASS_CODE.FORMAT", title: "cClassTrib com formato inválido", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, present("item.ibs_cbs.class_code")] },
  assert: { "field" => "item.ibs_cbs.class_code", "op" => "regex", "value" => "^\\d{6}$" },
  message: "cClassTrib {{item.ibs_cbs.class_code}} deve ter 6 dígitos.")

seed_rule!("IBSCBS.NFCE.GROUP", title: "NFC-e sem grupo IBS/CBS", scope: "item", severity: "error", effective_from: Date.new(2026, 8, 3), tags: %w[ibs_cbs reforma nfce],
  applies_when: { "all" => [issuer, eq("doc.model", "65"), goods] },
  assert: eq("item.ibs_cbs.present", true),
  message: "NFC-e emitida após 03/08/2026 sem grupo IBS/CBS no item.")

# ------------------------------------------------------------------ Cross-document / eventos
seed_rule!("DOC.NUMBERING.ORDER", title: "Numeração fora da ordem cronológica", scope: "cross_document", severity: "warning", effective_from: old, tags: %w[integrity],
  primitive: { "name" => "numbering_order", "params" => { "tolerance_days" => 0 } },
  message: "NF {{number}} (série {{series}}) emitida em {{issued_at}}, antes da NF {{previous_number}} emitida em {{previous_issued_at}}.")

seed_rule!("DOC.EVENT.CONSISTENCY", title: "Eventos incoerentes (cancelamento tardio, CC-e em cancelada, devolução de cancelada)", scope: "cross_document", severity: "warning", effective_from: old, tags: %w[events],
  primitive: { "name" => "event_consistency", "params" => { "cancellation_deadline_hours" => 24, "check" => "all" } },
  message: "Evento incoerente: {{problem}}.")

# ------------------------------------------------------------------ Cenário (desconfiar do gabarito)
seed_rule!("SCENARIO.REGIME.SIMPLES_VS_NORMAL", title: "Cenário Simples, mas as notas declaram regime normal (CRT 3)", scope: "scenario", severity: "warning", effective_from: old, tags: %w[scenario regime],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "tax_regime", "when_field_is" => "simples_nacional", "threshold" => "0.5", "evidence" => eq("doc.issuer.crt", "3") } },
  message: "{{share_pct}}% dos itens estão em notas com CRT 3 (regime normal), mas o cenário é Simples Nacional. O cliente mudou de regime?")

seed_rule!("SCENARIO.REGIME.NORMAL_VS_SIMPLES", title: "Cenário Lucro Presumido/Real, mas as notas declaram Simples (CRT 1)", scope: "scenario", severity: "warning", effective_from: old, tags: %w[scenario regime],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "tax_regime", "when_field_is" => "lucro_presumido", "threshold" => "0.5", "evidence" => inn("doc.issuer.crt", %w[1 2 4]) } },
  message: "{{share_pct}}% dos itens estão em notas com CRT de Simples Nacional, mas o cenário é Lucro Presumido.")

seed_rule!("SCENARIO.REGIME.REAL_VS_SIMPLES", title: "Cenário Lucro Real, mas as notas declaram Simples (CRT 1)", scope: "scenario", severity: "warning", effective_from: old, tags: %w[scenario regime],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "tax_regime", "when_field_is" => "lucro_real", "threshold" => "0.5", "evidence" => inn("doc.issuer.crt", %w[1 2 4]) } },
  message: "{{share_pct}}% dos itens estão em notas com CRT de Simples Nacional, mas o cenário é Lucro Real.")

seed_rule!("SCENARIO.NFCE.DISAGREEMENT", title: "Cenário sem NFC-e, mas o cliente emite NFC-e", scope: "scenario", severity: "warning", effective_from: old, tags: %w[scenario nfce],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "uses_nfce", "when_field_is" => false, "threshold" => "0.0", "evidence" => eq("doc.model", "65") } },
  message: "{{matching_items}} item(ns) em NFC-e, mas o cenário indica que o cliente não emite NFC-e.")

seed_rule!("SCENARIO.FINAL_CONSUMER.DISAGREEMENT", title: "Cenário sem consumidor final, mas as notas são a consumidor final", scope: "scenario", severity: "warning", effective_from: old, tags: %w[scenario],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "sells_to_final_consumer", "when_field_is" => false, "threshold" => "0.2", "evidence" => eq("doc.operation.final_consumer", true) } },
  message: "{{share_pct}}% dos itens estão em notas a consumidor final, mas o cenário diz que o cliente não vende a consumidor final.")

seed_rule!("SCENARIO.EXPORTS.DISAGREEMENT", title: "Cenário sem exportação, mas há CFOP 7xxx", scope: "scenario", severity: "info", effective_from: old, tags: %w[scenario],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "exports", "when_field_is" => false, "threshold" => "0.0", "evidence" => { "field" => "item.product.cfop", "op" => "starts_with", "value" => "7" } } },
  message: "{{matching_items}} item(ns) com CFOP de exportação, mas o cenário indica que o cliente não exporta.")

puts "rules (complete): #{Rules::Rule.count}"
