load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true) && respond_to?(:seed_rule!, true)
# Regras adicionais (ARQUITETURA.md §11). Todas dado; reutiliza seed_rule! de 03_rules.rb.
issuer = { "field" => "doc.role", "op" => "eq", "value" => "issuer" }
# Regimes vêm de 00_helpers.rb: ICMS (MEI = Simples; excesso de sublimite = normal) e federais (IPI/PIS/COFINS no DAS também no excesso).
simples_icms = regime_in(simples_icms_regimes)
normal_icms = regime_in(normal_icms_regimes)
normal_federal = regime_in(normal_federal_regimes)
goods = { "field" => "item.is_service", "op" => "eq", "value" => false }

seed_rule!("PISCOFINS.CST.REGIME", title: "CST de PIS/COFINS × regime", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins regime],
  applies_when: { "all" => [issuer, goods, { "field" => "item.pis.cst", "op" => "present" }, { "field" => "doc.operation.direction_declared", "op" => "eq", "value" => "outbound" }] },
  assert: { "if" => { "field" => "scenario.pis_cofins.regime", "op" => "eq", "value" => "simples" },
            "then" => { "field" => "item.pis.cst", "op" => "in", "value" => %w[49 04 06 07 08] },
            "else" => { "any" => [{ "field" => "item.pis.cst", "op" => "in", "value" => %w[01 02 03] },
                                  { "field" => "item.pis.taxation_kind", "op" => "in", "value" => %w[single_phase zero_rate exempt no_incidence suspended st] },
                                  # 49 "outras operações de saída" é o código das saídas sem receita (remessa, transferência,
                                  # bonificação, demonstração, retorno): só é erro quando a saída é venda ou exportação
                                  # sem a tabela de CFOP vigente na data a natureza fica AUSENTE (e `not_in` sobre ausente é evaluation_error):
                                  # sem saber se a saída é venda, não se acusa o 49 — mesmo tratamento dado ao CFOP fora da tabela ("unknown")
                                  { "all" => [{ "field" => "item.pis.cst", "op" => "eq", "value" => "49" },
                                              { "any" => [{ "field" => "item.cfop_nature", "op" => "absent" },
                                                          { "field" => "item.cfop_nature", "op" => "not_in", "value" => %w[sale export] }] }] }] } },
  message: "PIS CST {{item.pis.cst}} incompatível com o regime de PIS/COFINS do cenário ({{scenario.pis_cofins.regime}}) na operação {{item.cfop_nature}} (CFOP {{item.product.cfop}}).",
  explanation: "Optantes do Simples informam CST 49 (outras) nas saídas — ou 04/06 quando revendem monofásicos/alíquota zero com receita segregada; regime normal usa 01 (tributável) na venda, salvo monofásicos, alíquota zero, isenção ou suspensão. Nas saídas que não são receita (remessa 5.915, transferência 5.152, bonificação 5.910, demonstração 5.912, retorno 5.902) o 49 é o código correto também no regime normal — por isso a regra só cobra 01/02/03 quando o CFOP é de venda ou exportação.",
  legal_references: [{ "label" => "Tabela 4.3.3 do SPED (CST PIS/COFINS)" }, { "label" => "IN RFB 2.121/2022" }],
  group_by: ["item.pis.cst"])

seed_rule!("PISCOFINS.RATE.REGIME", title: "Alíquotas de PIS/COFINS × regime cumulativo/não cumulativo", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), effective_until: Date.new(2026, 12, 31), tags: %w[pis cofins],
  applies_when: { "all" => [issuer, normal_federal, { "field" => "item.pis.cst", "op" => "eq", "value" => "01" }, { "field" => "item.pis.rate", "op" => "present" }, { "field" => "item.cofins.rate", "op" => "present" }] },
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

seed_rule!("ICMS.SIMPLES.NO_HIGHLIGHT", title: "Simples Nacional destacando ICMS próprio", scope: "item", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[icms simples_nacional],
  applies_when: { "all" => [issuer, simples_icms, { "field" => "item.icms.csosn", "op" => "in", "value" => %w[101 102 103 300 400] }] },
  assert: { "any" => [{ "field" => "item.icms.amount", "op" => "absent" }, { "field" => "item.icms.amount", "op" => "lte", "value" => 0 }] },
  explanation: "Os grupos ICMSSN101/102/103/300/400 do leiaute nem têm campo de vICMS, e a SEFAZ rejeita o que estiver fora do schema: o achado só aparece em XML fora do padrão (ou lido de outra origem) — por isso warning.",
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
  applies_when: { "all" => [issuer, normal_icms, goods, { "field" => "doc.operation.scope", "op" => "eq", "value" => "interstate" }, { "field" => "doc.operation.direction", "op" => "eq", "value" => "outbound" },
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

seed_rule!("NFCE.RECIPIENT.NON_TAXPAYER", title: "NFC-e para contribuinte de ICMS", scope: "document", severity: "warning", effective_from: Date.new(2013, 1, 1), tags: %w[nfce],
  applies_when: { "all" => [issuer, { "field" => "doc.model", "op" => "eq", "value" => "65" }, { "field" => "doc.recipient.ie_indicator", "op" => "present" }] },
  assert: { "field" => "doc.recipient.ie_indicator", "op" => "neq", "value" => "taxpayer" },
  explanation: "A SEFAZ rejeita NFC-e com indIEDest=1 (rejeição 856). Num XML autorizado o achado indica indIEDest lido/gravado errado — por isso warning. A venda a CNPJ segue permitida na NFC-e (Ajuste SINIEF 12/2026), desde que o destinatário não seja contribuinte de ICMS.",
  legal_references: [{ "label" => "Ajuste SINIEF 07/05" }, { "label" => "Ajuste SINIEF 12/2026" }],
  message: "NFC-e emitida para destinatário contribuinte de ICMS (indIEDest=1); a operação exige NF-e modelo 55.")

# Compara com o CFOP dos itens, não com doc.operation.nature: a derivação força nature = *_return quando finNFe = 4
# (CANONICO §8), e com isso o ramo "finNFe 4 sem CFOP de devolução" nunca era alcançado.
seed_rule!("CFOP.RETURN.PURPOSE", title: "CFOP de devolução sem finalidade de devolução (ou vice-versa)", scope: "document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[cfop return],
  applies_when: { "all" => [issuer, { "field" => "doc.operation.mixed_cfop", "op" => "eq", "value" => false },
                            { "none" => "doc.items", "as" => "i", "where" => { "any" => [{ "field" => "i.cfop_nature", "op" => "absent" }, { "field" => "i.cfop_nature", "op" => "eq", "value" => "unknown" }] } }] },
  assert: { "if" => { "some" => "doc.items", "as" => "i", "where" => { "field" => "i.cfop_nature", "op" => "in", "value" => %w[sale_return purchase_return] } },
            "then" => { "field" => "doc.issuance.purpose", "op" => "eq", "value" => "return" },
            "else" => { "field" => "doc.issuance.purpose", "op" => "neq", "value" => "return" } },
  explanation: "CFOP 1.20x/2.20x/5.20x/6.20x (e 1.410/1.411/5.410/5.411) é devolução e exige finNFe = 4; e a nota com finNFe = 4 precisa sair com CFOP de devolução. Nota de ajuste/complemento usa finNFe 2/3 com o CFOP da operação original.",
  message: "CFOPs {{doc.operation.cfops}} não combinam com finNFe = {{doc.issuance.purpose}}.")

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
  applies_when: { "all" => [issuer, goods, { "field" => "item.st_applicable_by_catalog", "op" => "present" }, { "field" => "doc.operation.direction", "op" => "eq", "value" => "outbound" },
                            { "field" => "doc.recipient.ie_indicator", "op" => "eq", "value" => "taxpayer" }, { "field" => "doc.operation.final_consumer", "op" => "eq", "value" => false }] },
  assert: { "if" => { "field" => "item.st_applicable_by_catalog", "op" => "eq", "value" => true },
            "then" => { "any" => [{ "field" => "item.icms.taxation_kind", "op" => "in", "value" => %w[taxed_with_st st_withheld exempt_with_st reduced_base_with_st simples_with_credit_st simples_without_credit_st] }, { "field" => "item.icms_st.highlights_st", "op" => "eq", "value" => true }] },
            "else" => { "all" => [{ "field" => "item.icms.taxation_kind", "op" => "not_in", "value" => %w[taxed_with_st st_withheld] }] } },
  message: "NCM {{item.product.ncm}} na UF {{doc.operation.destination_uf}}: a tabela indica ST aplicável = {{item.st_applicable_by_catalog}}, mas o item usa CST/CSOSN {{item.icms.situation_code}} ({{item.icms.taxation_kind}}). Esperado com ST: CST 10/30/70 ou 60 (retida), CSOSN 201/202/203 ou 500; sem ST: nenhum código de ST.",
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

retire_rule!("DOC.RETURN.ORIGINAL", "dividida em DOC.RETURN.ORIGINAL_MISSING, DOC.RETURN.EXCEEDS_ORIGINAL e DOC.RETURN.MIRROR", on: Date.new(2026, 8, 30))

seed_rule!("DOC.RETURN.ORIGINAL_MISSING", title: "Devolução de venda referencia nota do próprio cliente que não está na base", scope: "cross_document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[return],
  primitive: { "name" => "return_references_original", "params" => { "check" => "missing" } },
  message: "Devolução referencia a NF-e {{referenced_access_key}} (emitida pelo próprio cliente), que não foi enviada. Envie o período da venda para validar o espelhamento.",
  explanation: "Sem a nota original não é possível conferir CST/CSOSN, alíquotas, CFOP e quantidades devolvidas.")

seed_rule!("DOC.RETURN.EXCEEDS_ORIGINAL", title: "Quantidade devolvida (acumulada) maior que a vendida", scope: "cross_document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[return],
  primitive: { "name" => "return_references_original", "params" => { "check" => "exceeds", "tolerance" => "0.0001" } },
  message: "Produto {{product_code}}: devolvido {{returned_quantity}} de {{original_quantity}} vendido na NF-e {{original_access_key}}.")

seed_rule!("DOC.RETURN.MIRROR", title: "Devolução de venda não espelha a tributação/CFOP da nota original", scope: "cross_document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[return icms],
  # PIS/COFINS ficam fora do espelho: a devolução é ENTRADA e o CST de entrada é 50-99 (Tabela 4.3.3), o oposto do
  # CST de saída da venda — exigir o mesmo código contradiria PISCOFINS.CST.DIRECTION e nenhuma nota satisfaria as duas.
  primitive: { "name" => "return_references_original", "params" => { "check" => "mirror", "mirror_fields" => %w[icms.situation_code icms.rate],
    # CFOP da venda => CFOPs de devolução aceitos (Ajuste SINIEF s/nº 1970, Anexo — CFOP)
    # Cobertura intencionalmente parcial: CFOP de venda fora deste mapa não é conferido (a primitiva pula em silêncio).
    # Preferimos o falso negativo ao falso positivo em `error` — cada par novo exige confirmar o CFOP de devolução no Anexo.
    "cfop_mirror" => { "5101" => %w[1201], "6101" => %w[2201], "5102" => %w[1202], "6102" => %w[2202], "5401" => %w[1410], "6401" => %w[2410], "5403" => %w[1411], "6403" => %w[2411], "5405" => %w[1411 1202], "6404" => %w[2411 2202],
                       "5103" => %w[1201], "5104" => %w[1202], "5105" => %w[1201], "5106" => %w[1202], "6107" => %w[2201], "6108" => %w[2202],
                       # ZFM/ALC (5.109/6.109 produção própria, 5.110/6.110 de terceiros) e ativo imobilizado (x.551 → devolução x.553)
                       "5109" => %w[1201], "6109" => %w[2201], "5110" => %w[1202], "6110" => %w[2202], "5551" => %w[1553], "6551" => %w[2553],
                       "7101" => %w[3201], "7102" => %w[3202] } } },
  message: "Devolução da NF-e {{original_access_key}}, produto {{product_code}}: {{field}} = {{found}}, mas a original tem {{expected}}. A devolução espelha a venda (mesmo CST/CSOSN, alíquotas e CFOP de devolução correspondente).",
  explanation: "Na devolução de venda emitida pelo vendedor (NF-e de entrada, finNFe=4, CFOP 1.20x/2.20x referenciando a venda), a tributação reproduz a da nota original: Simples devolve com o mesmo CSOSN (101/102...) sem destaque; regime normal repete o CST e destaca o ICMS para recuperar o crédito. O CSOSN 900 aplica-se à devolução de COMPRA (destaque do ICMS do fornecedor), não à de venda. CFOP: 5.101→1.201, 5.102→1.202, 5.401→1.410, 5.403/5.405→1.411 (e 2.xxx para interestaduais).",
  legal_references: [{ "label" => "Ajuste SINIEF 07/05 (finNFe 4 e NFref)" }, { "label" => "Ajuste SINIEF s/nº 1970, Anexo — CFOP 1.201/1.202/1.410/1.411" }, { "label" => "RICMS/SP art. 57 (crédito na devolução)" }])

seed_rule!("SCENARIO.ST.DISAGREEMENT", title: "Cenário sem ST, mas as notas destacam ST", scope: "scenario", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[scenario st],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "st.applies", "when_field_is" => false, "threshold" => "0.2",
    "evidence" => { "any" => [{ "field" => "item.icms_st.highlights_st", "op" => "eq", "value" => true }, { "field" => "item.icms.situation_code", "op" => "in", "value" => %w[60 500 10 30 70 201 202 203] }] } } },
  message: "{{share_pct}}% dos itens ({{matching_items}} de {{total_items}}) têm ST destacada ou retida, mas o cenário indica que o cliente não opera com ST. Revise o cenário.")

seed_rule!("SCENARIO.IPI.DISAGREEMENT", title: "Cenário sem IPI, mas as notas destacam IPI", scope: "scenario", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[scenario ipi],
  primitive: { "name" => "scenario_field_disagreement", "params" => { "field" => "ipi_taxpayer", "when_field_is" => false, "threshold" => "0.1",
    # item sem grupo IPI não tem ipi.amount (ausência ≠ zero): sem o present, gt vira evaluation_error
    "evidence" => { "all" => [{ "field" => "item.ipi.amount", "op" => "present" },
                              { "field" => "item.ipi.amount", "op" => "gt", "value" => 0 }] } } },
  message: "{{share_pct}}% dos itens destacam IPI, mas o cenário diz que o cliente não é contribuinte de IPI. Revise o cenário (indústria/equiparado?).")

puts "rules (extra): #{Rules::Rule.count}"
