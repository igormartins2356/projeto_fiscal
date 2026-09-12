load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_rule!, true)

issuer = { "field" => "doc.role", "op" => "eq", "value" => "issuer" }
# Regimes vêm de 00_helpers.rb: no ICMS o MEI é Simples (CSOSN) e o excesso de sublimite é regime normal (CST).
simples_icms = regime_in(simples_icms_regimes)
normal_icms = regime_in(normal_icms_regimes)

# ICMS.CSOSN.SALE_RETURN foi removida (30/08/2026): devolução de venda emitida pelo próprio optante espelha a nota original (CSOSN da venda);
# o CSOSN 900 é o caso da devolução de COMPRA (destaque do ICMS do fornecedor). Substituída por DOC.RETURN.MIRROR.
retire_rule!("ICMS.CSOSN.SALE_RETURN", "devolução de venda espelha a original; ver DOC.RETURN.MIRROR", on: Date.new(2026, 8, 30))

seed_rule!("ICMS.REGIME.SITUATION_FIELD", title: "CST × CSOSN coerente com o regime do cenário", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms regime],
  applies_when: { "all" => [issuer, { "field" => "item.is_service", "op" => "eq", "value" => false }, { "field" => "item.icms.situation_field", "op" => "neq", "value" => "absent" }] },
  assert: { "if" => simples_icms, "then" => { "field" => "item.icms.situation_field", "op" => "eq", "value" => "csosn" }, "else" => { "field" => "item.icms.situation_field", "op" => "eq", "value" => "cst" } },
  message: "Item usa {{item.icms.situation_field}} ({{item.icms.situation_code}}), incompatível com o regime {{scenario.tax_regime}} do cenário.",
  explanation: "Optantes do Simples Nacional (CRT 1) e MEI (CRT 4) informam CSOSN (grupo ICMSSN); regime normal informa CST. O Simples com excesso de sublimite (CRT 2) recolhe o ICMS fora do Simples (LC 123/2006 arts. 19 e 20) e por isso também informa CST. Divergência indica cenário desatualizado ou ERP configurado com o regime errado.",
  legal_references: [{ "label" => "LC 123/2006, arts. 19 e 20" }, { "label" => "Ajuste SINIEF 07/05, Tabela B (CSOSN)" }],
  group_by: ["item.icms.situation_field"])

seed_rule!("ICMS.CRT.SCENARIO", title: "CRT da nota × regime do cenário", scope: "document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[icms regime scenario],
  applies_when: { "all" => [issuer, { "field" => "doc.issuer.tax_regime", "op" => "neq", "value" => "unknown" }] },
  assert: { "any" => [
    { "all" => [{ "field" => "scenario.tax_regime", "op" => "eq", "value" => "simples_nacional" }, { "field" => "doc.issuer.tax_regime", "op" => "eq", "value" => "simples_nacional" }] },
    { "all" => [{ "field" => "scenario.tax_regime", "op" => "eq", "value" => "mei" }, { "field" => "doc.issuer.tax_regime", "op" => "eq", "value" => "mei" }] },
    # excesso de sublimite: muito ERP segue emitindo CRT 1 no ano da mudança — não é o achado desta regra
    { "all" => [{ "field" => "scenario.tax_regime", "op" => "eq", "value" => "simples_nacional_excess" }, { "field" => "doc.issuer.tax_regime", "op" => "in", "value" => %w[simples_nacional_excess simples_nacional] }] },
    { "all" => [regime_in(normal_federal_regimes), { "field" => "doc.issuer.tax_regime", "op" => "eq", "value" => "normal" }] }
  ] },
  explanation: "CRT 1 = Simples Nacional, 2 = Simples com excesso de sublimite (ICMS/ISS fora do Simples), 3 = regime normal, 4 = MEI. A regra compara o CRT declarado com o regime do cenário; cada regime tem o seu CRT.",
  message: "A nota declara CRT {{doc.issuer.crt}} ({{doc.issuer.tax_regime}}), mas o cenário do cliente é {{scenario.tax_regime}}. Revise o cenário ou o cadastro no ERP.")

seed_rule!("CFOP.SCOPE.MATCH", title: "CFOP × âmbito da operação (idDest)", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[cfop],
  applies_when: { "all" => [issuer, { "field" => "doc.operation.scope", "op" => "present" }] },
  assert: { "field" => "item.cfop_scope", "op" => "eq", "value" => { "ref" => "doc.operation.scope" } },
  message: "CFOP {{item.product.cfop}} é de operação {{item.cfop_scope}}, mas a nota indica operação {{doc.operation.scope}} (idDest).",
  group_by: ["item.product.cfop", "doc.operation.scope"])

seed_rule!("CFOP.KNOWN", title: "CFOP fora da tabela vigente", scope: "item", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[cfop],
  applies_when: { "field" => "item.cfop_known", "op" => "present" },
  assert: { "field" => "item.cfop_known", "op" => "eq", "value" => true },
  explanation: "A tabela de CFOP é curadoria nossa (DATA_SOURCES §1.3: classe B, sem importador oficial). Um CFOP fora dela pode ser código legítimo ainda não catalogado — por isso warning, e não error. A SEFAZ rejeita CFOP inexistente (rejeição 508/509), então o mais provável num XML autorizado é a lacuna ser nossa.",
  message: "CFOP {{item.product.cfop}} não consta da tabela vigente na data de emissão.",
  group_by: ["item.product.cfop"])

seed_rule!("DOC.RETURN.REFERENCE", title: "Devolução sem nota referenciada", scope: "document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[return],
  applies_when: { "all" => [issuer, { "field" => "doc.issuance.purpose", "op" => "eq", "value" => "return" }] },
  assert: { "some" => "doc.references", "as" => "r", "where" => { "any" => [{ "field" => "r.access_key", "op" => "present" }, { "field" => "r.nf_model_1", "op" => "present" }] } },
  explanation: "A SEFAZ já rejeita finNFe=4 sem NFref (rejeição 321), então num XML autorizado o achado costuma ser leitura nossa do grupo NFref — daí warning. Vale para NF-e (refNFe) e para nota modelo 1 (refNF), aceita pela mesma exigência.",
  legal_references: [{ "label" => "Ajuste SINIEF 07/05 (NFref)" }, { "label" => "MOC — rejeição 321" }],
  message: "Nota de devolução (finNFe=4) sem nota referenciada (refNFe/refNF).")

seed_rule!("DOC.TOTALS.ITEMS_SUM", title: "Totais da nota × soma dos itens", scope: "document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[integrity],
  primitive: { "name" => "items_sum_matches_totals", "params" => { "fields" => %w[products icms_base icms icms_st ipi pis cofins], "tolerance" => "0.01" } },
  explanation: "A SEFAZ valida os totais na autorização (NT 2015.003, rejeições 5xx). Num XML autorizado a divergência costuma vir de item fora do total (indTot=0), rateio de frete/desconto ou da nossa soma — por isso warning: confira antes de corrigir a escrituração.",
  message: "Total {{field}} da nota ({{total}}) diverge da soma dos itens ({{items_sum}}).",
  group_by: ["field"])

seed_rule!("ICMS.AMOUNT.CALC", title: "vICMS ≠ vBC × alíquota", scope: "item", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[icms],
  params: { "tolerance" => "0.02" },
  explanation: "A SEFAZ já rejeita vICMS ≠ vBC × pICMS na autorização (NT 2015.003). Num XML autorizado sobra o arredondamento por item e o ICMS por dentro em regimes especiais — por isso warning.",
  applies_when: { "all" => [{ "field" => "item.icms.expected_amount", "op" => "present" }, { "field" => "item.icms.amount", "op" => "present" }] },
  assert: { "field" => "item.icms.amount", "op" => "approx", "value" => { "ref" => "item.icms.expected_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "ICMS destacado {{item.icms.amount}} difere de base × alíquota = {{item.icms.expected_amount}}.")

seed_rule!("ICMS.RATE.INTERSTATE", title: "Alíquota interestadual de ICMS", scope: "item", severity: "error", effective_from: Date.new(2013, 1, 1), tags: %w[icms interstate],
  let: [{ "lookup" => "icms_interstate_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, { "ref" => "doc.operation.destination_uf" }, { "ref" => "item.icms.origin_category" }], "as" => "expected" }],
  explanation: "Res. Senado 22/1989 (7%/12%) e 13/2012 (4% para origem 1, 2, 3 e 8). Antes de 2016 (EC 87/2015) a venda interestadual a não contribuinte usava a alíquota interna — por isso a regra só alcança não contribuintes a partir de 01/01/2016.",
  applies_when: { "all" => [issuer, normal_icms, { "field" => "doc.operation.scope", "op" => "eq", "value" => "interstate" },
                            { "any" => [{ "field" => "doc.recipient.ie_indicator", "op" => "eq", "value" => "taxpayer" }, { "field" => "doc.reference_date", "op" => "gte", "value" => "2016-01-01" }] },
                            { "field" => "item.icms.taxation_kind", "op" => "in", "value" => %w[taxed taxed_with_st reduced_base reduced_base_with_st] },
                            { "field" => "expected", "op" => "present" }, { "field" => "item.icms.rate", "op" => "present" }] },
  assert: { "field" => "item.icms.rate", "op" => "approx", "value" => { "ref" => "expected.rate" }, "tolerance" => "0.001" },
  message: "Alíquota interestadual {{item.icms.rate}}% para {{doc.operation.origin_uf}}→{{doc.operation.destination_uf}} (origem {{item.icms.origin}}); esperado {{expected.rate}}%.",
  legal_references: [{ "label" => "Resolução Senado 22/1989" }, { "label" => "Resolução Senado 13/2012" }],
  group_by: ["doc.operation.destination_uf", "item.icms.rate", "expected.rate"])

seed_rule!("DOC.DUPLICATE.NUMBER_SERIES", title: "Mesmo número/série autorizado com chaves diferentes", scope: "cross_document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[integrity],
  primitive: { "name" => "duplicate_document", "params" => { "match_on" => "number_series_cnpj", "only_authorized" => true } },
  message: "NF-e {{issuance.number}}/{{issuance.series}} autorizada mais de uma vez com chaves diferentes: {{access_keys}}.")

ibs_applies = { "all" => [issuer, { "field" => "item.is_service", "op" => "eq", "value" => false }] }
seed_rule!("IBSCBS.GROUP.REQUIRED", version: 1, title: "Grupo IBS/CBS ausente (obrigatório desde 01/01/2026; SEFAZ só rejeita desde 03/08/2026)", scope: "item", severity: "error",
  effective_from: Date.new(2026, 1, 1), effective_until: Date.new(2026, 8, 2), tags: %w[ibs_cbs reforma],
  applies_when: ibs_applies, assert: { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true },
  message: "Item sem grupo IBS/CBS. Obrigatório desde 01/01/2026 (NT 2025.002); a SEFAZ autorizou porque a rejeição em produção só começou em 03/08/2026.",
  legal_references: [{ "label" => "LC 214/2025" }, { "label" => "NT 2025.002 v1.40" }])
seed_rule!("IBSCBS.GROUP.REQUIRED", version: 2, title: "Grupo IBS/CBS ausente", scope: "item", severity: "warning", effective_from: Date.new(2026, 8, 3), tags: %w[ibs_cbs reforma],
  applies_when: ibs_applies, assert: { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true },
  explanation: "Desde 03/08/2026 a SEFAZ rejeita o item sem grupo IBS/CBS (NT 2025.002 v1.40). Se o XML foi autorizado sem o grupo, o mais provável é falha de leitura/integridade do arquivo — por isso warning, ao contrário da v1 (01/01/2026 a 02/08/2026), quando a nota era autorizada mesmo errada.",
  message: "Item sem grupo IBS/CBS em documento autorizado após 03/08/2026 — verifique a integridade do XML.",
  legal_references: [{ "label" => "NT 2025.002 v1.40" }])

cbs_schedule_applies = { "all" => [issuer, { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true }, { "field" => "item.ibs_cbs.cst", "op" => "eq", "value" => "000" },
                                   { "field" => "item.ibs_cbs.cbs.rate", "op" => "present" }, { "field" => "item.ibs_cbs.schedule_rates.cbs", "op" => "present" }] }
cbs_schedule_assert = { "field" => "item.ibs_cbs.cbs.rate", "op" => "approx", "value" => { "ref" => "item.ibs_cbs.schedule_rates.cbs" }, "tolerance" => "0.001" }
# 2026 é a alíquota-teste fixada em lei (0,9%): divergir é erro. De 2027 em diante a alíquota do cronograma ainda é
# estimativa até a Resolução do Senado (DATA_SOURCES §1.11: estimativa não gera error) — versão própria, em warning.
seed_rule!("IBSCBS.CBS.RATE_SCHEDULE", version: 1, title: "Alíquota CBS × cronograma do ano (alíquota-teste de 2026)", scope: "item", severity: "error",
  effective_from: Date.new(2026, 1, 1), effective_until: Date.new(2026, 12, 31), tags: %w[ibs_cbs reforma],
  applies_when: cbs_schedule_applies, assert: cbs_schedule_assert,
  message: "Alíquota CBS {{item.ibs_cbs.cbs.rate}}% diverge do cronograma vigente ({{item.ibs_cbs.schedule_rates.cbs}}%).",
  legal_references: [{ "label" => "LC 214/2025 art. 343" }],
  group_by: ["item.ibs_cbs.cbs.rate"])
seed_rule!("IBSCBS.CBS.RATE_SCHEDULE", version: 2, title: "Alíquota CBS × cronograma do ano (estimativa a partir de 2027)", scope: "item", severity: "warning",
  effective_from: Date.new(2027, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: cbs_schedule_applies, assert: cbs_schedule_assert,
  explanation: "A alíquota de referência da CBS a partir de 2027 só é definitiva com a Resolução do Senado (LC 214/2025 art. 348); até lá o cronograma guarda uma estimativa e a divergência é aviso para conferência, nunca erro (DATA_SOURCES §1.11).",
  message: "Alíquota CBS {{item.ibs_cbs.cbs.rate}}% diverge do cronograma do ano ({{item.ibs_cbs.schedule_rates.cbs}}%), que ainda é estimativa — confirme a alíquota publicada antes de corrigir.",
  legal_references: [{ "label" => "LC 214/2025 arts. 343 e 348" }],
  group_by: ["item.ibs_cbs.cbs.rate"])

puts "rules: #{Rules::Rule.count}"
