# Regras adicionais (ARQUITETURA.md §11). Todas dado; reutiliza seed_rule! de 03_rules.rb.
issuer = { "field" => "doc.role", "op" => "eq", "value" => "issuer" }
simples = { "field" => "scenario.tax_regime", "op" => "in", "value" => %w[simples_nacional simples_nacional_excess mei] }
normal_regime = { "field" => "scenario.tax_regime", "op" => "in", "value" => %w[lucro_presumido lucro_real] }
goods = { "field" => "item.is_service", "op" => "eq", "value" => false }

seed_rule!("PISCOFINS.CST.REGIME", title: "CST de PIS/COFINS × regime", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins regime],
  applies_when: { "all" => [issuer, goods, { "field" => "item.pis.cst", "op" => "present" }] },
  assert: { "if" => { "field" => "scenario.pis_cofins.regime", "op" => "eq", "value" => "simples" },
            "then" => { "field" => "item.pis.cst", "op" => "in", "value" => %w[49 99 08 07] },
            "else" => { "any" => [{ "field" => "item.pis.cst", "op" => "in", "value" => %w[01 02 03] }, { "field" => "item.pis.taxation_kind", "op" => "in", "value" => %w[single_phase zero_rate exempt no_incidence suspended st] }] } },
  message: "PIS CST {{item.pis.cst}} incompatível com o regime de PIS/COFINS do cenário ({{scenario.pis_cofins.regime}}).",
  explanation: "Optantes do Simples informam CST 49 (outras) nas saídas; regime normal usa 01 (tributável) salvo monofásicos, alíquota zero, isenção ou suspensão.",
  group_by: ["item.pis.cst"])

seed_rule!("PISCOFINS.RATE.REGIME", title: "Alíquotas de PIS/COFINS × regime cumulativo/não cumulativo", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins],
  applies_when: { "all" => [issuer, normal_regime, { "field" => "item.pis.cst", "op" => "eq", "value" => "01" }, { "field" => "item.pis.rate", "op" => "present" }, { "field" => "item.cofins.rate", "op" => "present" }] },
  assert: { "if" => { "field" => "scenario.pis_cofins.regime", "op" => "eq", "value" => "non_cumulative" },
            "then" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "1.65", "tolerance" => "0.001" }, { "field" => "item.cofins.rate", "op" => "approx", "value" => "7.60", "tolerance" => "0.001" }] },
            "else" => { "all" => [{ "field" => "item.pis.rate", "op" => "approx", "value" => "0.65", "tolerance" => "0.001" }, { "field" => "item.cofins.rate", "op" => "approx", "value" => "3.00", "tolerance" => "0.001" }] } },
  message: "PIS {{item.pis.rate}}% / COFINS {{item.cofins.rate}}% divergem do regime {{scenario.pis_cofins.regime}} (esperado 0,65/3,00 cumulativo ou 1,65/7,60 não cumulativo).",
  legal_references: [{ "label" => "Lei 9.718/98" }, { "label" => "Leis 10.637/02 e 10.833/03" }],
  group_by: ["item.pis.rate", "item.cofins.rate"])

seed_rule!("IPI.NON_TAXPAYER.HIGHLIGHT", title: "IPI destacado por não contribuinte de IPI", scope: "item", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[ipi],
  applies_when: { "all" => [issuer, { "field" => "scenario.ipi_taxpayer", "op" => "eq", "value" => false }, { "field" => "item.ipi.amount", "op" => "present" }] },
  assert: { "field" => "item.ipi.amount", "op" => "lte", "value" => 0 },
  message: "IPI de {{item.ipi.amount}} destacado, mas o cenário indica que o cliente não é contribuinte de IPI (comércio). Confira o cadastro do produto ou o cenário.")

seed_rule!("ICMS.SIMPLES.NO_HIGHLIGHT", title: "Simples Nacional destacando ICMS próprio", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms simples_nacional],
  applies_when: { "all" => [issuer, simples, { "field" => "item.icms.csosn", "op" => "in", "value" => %w[101 102 103 300 400] }] },
  assert: { "any" => [{ "field" => "item.icms.amount", "op" => "absent" }, { "field" => "item.icms.amount", "op" => "lte", "value" => 0 }] },
  message: "CSOSN {{item.icms.csosn}} com vICMS {{item.icms.amount}}: optante do Simples não destaca ICMS próprio (só crédito no CSOSN 101/201).",
  group_by: ["item.icms.csosn"])

seed_rule!("ICMS.BASE.CALC", title: "Base de cálculo do ICMS × valor da operação", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms],
  params: { "tolerance" => "0.02" },
  applies_when: { "all" => [issuer, { "field" => "item.icms.expected_base_reliable", "op" => "eq", "value" => true }, { "field" => "item.icms.base_amount", "op" => "present" }, { "field" => "item.icms.base_amount", "op" => "gt", "value" => 0 },
                            { "field" => "item.icms.taxation_kind", "op" => "in", "value" => %w[taxed taxed_with_st reduced_base reduced_base_with_st] }] },
  assert: { "field" => "item.icms.base_amount", "op" => "approx", "value" => { "ref" => "item.icms.expected_base_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "Base de ICMS {{item.icms.base_amount}} difere do esperado {{item.icms.expected_base_amount}} (valor líquido do item com redução de {{item.icms.base_reduction_pct}}%). Desconto ou frete não rateados?",
  group_by: ["item.icms.base_reduction_pct"])

seed_rule!("DIFAL.REQUIRED", title: "DIFAL ausente em venda interestadual a não contribuinte", scope: "item", severity: "error", effective_from: Date.new(2016, 1, 1), tags: %w[icms difal],
  applies_when: { "all" => [issuer, normal_regime, goods, { "field" => "doc.operation.scope", "op" => "eq", "value" => "interstate" }, { "field" => "doc.operation.direction", "op" => "eq", "value" => "outbound" },
                            { "field" => "doc.recipient.ie_indicator", "op" => "eq", "value" => "non_taxpayer" }, { "field" => "doc.operation.final_consumer", "op" => "eq", "value" => true },
                            { "field" => "item.icms.taxation_kind", "op" => "in", "value" => %w[taxed reduced_base] }] },
  assert: { "field" => "item.has_difal", "op" => "eq", "value" => true },
  message: "Venda interestadual a consumidor final não contribuinte sem grupo ICMSUFDest (DIFAL/EC 87/2015).",
  legal_references: [{ "label" => "EC 87/2015" }, { "label" => "Convênio ICMS 236/2021" }])

seed_rule!("NFCE.CFOP.INTRASTATE", title: "NFC-e com CFOP fora de 5xxx", scope: "item", severity: "error", effective_from: Date.new(2013, 1, 1), tags: %w[nfce cfop],
  applies_when: { "all" => [issuer, { "field" => "doc.model", "op" => "eq", "value" => "65" }] },
  assert: { "field" => "item.product.cfop", "op" => "starts_with", "value" => "5" },
  message: "NFC-e só admite operações internas (CFOP 5xxx); encontrado {{item.product.cfop}}.",
  group_by: ["item.product.cfop"])

seed_rule!("NFCE.RECIPIENT.NON_TAXPAYER", title: "NFC-e para contribuinte de ICMS", scope: "document", severity: "error", effective_from: Date.new(2013, 1, 1), tags: %w[nfce],
  applies_when: { "all" => [issuer, { "field" => "doc.model", "op" => "eq", "value" => "65" }, { "field" => "doc.recipient.ie_indicator", "op" => "present" }] },
  assert: { "field" => "doc.recipient.ie_indicator", "op" => "neq", "value" => "taxpayer" },
  message: "NFC-e emitida para destinatário contribuinte de ICMS (indIEDest=1); a operação exige NF-e modelo 55.")

seed_rule!("CFOP.RETURN.PURPOSE", title: "CFOP de devolução sem finalidade de devolução (ou vice-versa)", scope: "document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[cfop return],
  applies_when: { "all" => [issuer, { "field" => "doc.operation.mixed_cfop", "op" => "eq", "value" => false }] },
  assert: { "if" => { "field" => "doc.operation.nature", "op" => "in", "value" => %w[sale_return purchase_return] },
            "then" => { "field" => "doc.issuance.purpose", "op" => "eq", "value" => "return" },
            "else" => { "field" => "doc.issuance.purpose", "op" => "neq", "value" => "return" } },
  message: "CFOPs {{doc.operation.cfops}} ({{doc.operation.nature}}) não combinam com finNFe = {{doc.issuance.purpose}}.")

seed_rule!("NCM.VALID", title: "NCM inexistente na tabela vigente", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[ncm],
  applies_when: { "all" => [issuer, goods, { "field" => "item.ncm_valid", "op" => "present" }, { "field" => "item.ncm_generic", "op" => "eq", "value" => false }] },
  assert: { "field" => "item.ncm_valid", "op" => "eq", "value" => true },
  message: "NCM {{item.product.ncm}} não existe na tabela vigente em {{doc.reference_date}}.",
  group_by: ["item.product.ncm"])

seed_rule!("CEST.REQUIRED", title: "CEST ausente em NCM sujeito a ST", scope: "item", severity: "error", effective_from: Date.new(2018, 1, 1), tags: %w[cest st],
  applies_when: { "all" => [issuer, goods, { "field" => "item.expected_cest", "op" => "present" }, { "field" => "item.expected_cest", "op" => "not_empty" }] },
  assert: { "field" => "item.product.cest", "op" => "present" },
  message: "Item com NCM {{item.product.ncm}} enquadrado no Convênio ICMS 142/18 sem CEST informado.",
  legal_references: [{ "label" => "Convênio ICMS 142/2018" }], group_by: ["item.product.ncm"])

seed_rule!("ICMS.ST.CATALOG", title: "ST destacada/retida em NCM sem ST na UF (ou ausente quando devida)", scope: "item", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[icms st],
  applies_when: { "all" => [issuer, goods, { "field" => "item.st_applicable_by_catalog", "op" => "present" }, { "field" => "doc.operation.direction", "op" => "eq", "value" => "outbound" }] },
  assert: { "if" => { "field" => "item.st_applicable_by_catalog", "op" => "eq", "value" => true },
            "then" => { "any" => [{ "field" => "item.icms.taxation_kind", "op" => "in", "value" => %w[taxed_with_st st_withheld exempt_with_st reduced_base_with_st simples_with_credit_st simples_without_credit_st] }, { "field" => "item.icms_st.highlights_st", "op" => "eq", "value" => true }] },
            "else" => { "all" => [{ "field" => "item.icms.taxation_kind", "op" => "not_in", "value" => %w[taxed_with_st st_withheld] }] } },
  message: "Tratamento de ST do item (CST/CSOSN {{item.icms.situation_code}}) diverge da tabela de ST da UF {{doc.operation.destination_uf}} para o NCM {{item.product.ncm}}.",
  group_by: ["item.product.ncm", "item.icms.situation_code"])

seed_rule!("IBSCBS.CST_CLASS.COHERENT", title: "CST IBS/CBS × cClassTrib", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  let: [{ "lookup" => "ibs_cbs_class", "key" => [{ "ref" => "item.ibs_cbs.class_code" }], "as" => "klass" }],
  applies_when: { "all" => [issuer, { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true }, { "field" => "item.ibs_cbs.class_code", "op" => "present" }] },
  assert: { "all" => [{ "field" => "klass", "op" => "present" }, { "field" => "klass.cst", "op" => "eq", "value" => { "ref" => "item.ibs_cbs.cst" } }] },
  message: "cClassTrib {{item.ibs_cbs.class_code}} não existe na tabela vigente ou não corresponde ao CST {{item.ibs_cbs.cst}} (esperado {{klass.cst}}).",
  legal_references: [{ "label" => "NT 2025.002 / IT 2025.002" }], group_by: ["item.ibs_cbs.class_code", "item.ibs_cbs.cst"])

seed_rule!("DOC.NUMBERING.GAP", title: "Lacuna de numeração sem inutilização", scope: "cross_document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[integrity],
  primitive: { "name" => "numbering_gap", "params" => { "max_gap_ignored" => 0, "consider_invalidations" => true } },
  message: "Série {{series}} (modelo {{model}}): {{missing_count}} número(s) faltando entre {{missing_from}} e {{missing_to}} sem inutilização correspondente.")

seed_rule!("DOC.RETURN.ORIGINAL", title: "Devolução sem original na base ou excedendo a quantidade original", scope: "cross_document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[return],
  primitive: { "name" => "return_references_original", "params" => { "require_resolved" => true, "compare" => "quantity", "tolerance" => "0.0001" } },
  message: "Devolução: {{problem}} — original {{referenced_access_key}}{{original_access_key}} produto {{product_code}} (devolvido {{returned_quantity}} de {{original_quantity}}).")

seed_rule!("SCENARIO.ST.DISAGREEMENT", title: "Cenário sem ST, mas as notas destacam ST", scope: "scenario", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[scenario st],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "st.applies_any", "when_field_is" => false, "threshold" => "0.2",
    "evidence" => { "any" => [{ "field" => "item.icms_st.highlights_st", "op" => "eq", "value" => true }, { "field" => "item.icms.situation_code", "op" => "in", "value" => %w[60 500 10 30 70 201 202 203] }] } } },
  message: "{{share_pct}}% dos itens ({{matching_items}} de {{total_items}}) têm ST destacada ou retida, mas o cenário indica que o cliente não opera com ST. Revise o cenário.")

seed_rule!("SCENARIO.IPI.DISAGREEMENT", title: "Cenário sem IPI, mas as notas destacam IPI", scope: "scenario", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[scenario ipi],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "ipi_taxpayer", "when_field_is" => false, "threshold" => "0.1",
    "evidence" => { "field" => "item.ipi.amount", "op" => "gt", "value" => 0 } } },
  message: "{{share_pct}}% dos itens destacam IPI, mas o cenário diz que o cliente não é contribuinte de IPI. Revise o cenário (indústria/equiparado?).")

puts "rules (extra): #{Rules::Rule.count}"
