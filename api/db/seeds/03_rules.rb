def seed_rule!(code, **attrs)
  body = attrs.extract!(:let, :applies_when, :assert, :primitive, :message, :explanation, :legal_references, :params, :group_by, :suggested_fix).compact.transform_keys(&:to_s)
  Rules::Rule.find_or_create_by!(code:, version: attrs.fetch(:version, 1)) do |r|
    r.assign_attributes(attrs.merge(body:, state: "published", published_at: Time.current))
  end
end

issuer = { "field" => "doc.role", "op" => "eq", "value" => "issuer" }
simples = { "field" => "scenario.tax_regime", "op" => "eq", "value" => "simples_nacional" }
normal_regime = { "field" => "scenario.tax_regime", "op" => "in", "value" => %w[lucro_presumido lucro_real] }

seed_rule!("ICMS.CSOSN.SALE_RETURN", title: "CSOSN em devolução de venda (Simples)", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms simples_nacional sale_return],
  applies_when: { "all" => [issuer, simples, { "field" => "doc.operation.nature", "op" => "eq", "value" => "sale_return" }, { "field" => "item.icms.csosn", "op" => "present" }] },
  assert: { "field" => "item.icms.csosn", "op" => "eq", "value" => "900" },
  message: "Devolução de venda no Simples Nacional deve usar CSOSN 900; encontrado {{item.icms.csosn}} (CFOP {{item.product.cfop}}).",
  explanation: "Na devolução de venda, o Simples Nacional utiliza o CSOSN 900 (Outros), informando base e valor do ICMS conforme a nota original quando houver destaque.",
  legal_references: [{ "label" => "Ajuste SINIEF 07/05, Tabela B (CSOSN)" }],
  group_by: ["item.icms.csosn"])

seed_rule!("ICMS.REGIME.SITUATION_FIELD", title: "CST × CSOSN coerente com o regime do cenário", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms regime],
  applies_when: { "all" => [issuer, { "field" => "item.is_service", "op" => "eq", "value" => false }, { "field" => "item.icms.situation_field", "op" => "neq", "value" => "absent" }] },
  assert: { "if" => simples, "then" => { "field" => "item.icms.situation_field", "op" => "eq", "value" => "csosn" }, "else" => { "field" => "item.icms.situation_field", "op" => "eq", "value" => "cst" } },
  message: "Item usa {{item.icms.situation_field}} ({{item.icms.situation_code}}), incompatível com o regime {{scenario.tax_regime}} do cenário.",
  explanation: "Optantes do Simples Nacional informam CSOSN (grupo ICMSSN); regime normal informa CST. Divergência indica cenário desatualizado ou ERP configurado com o regime errado.",
  group_by: ["item.icms.situation_field"])

seed_rule!("ICMS.CRT.SCENARIO", title: "CRT da nota × regime do cenário", scope: "document", severity: "warning", effective_from: Date.new(2010, 1, 1), tags: %w[icms regime scenario],
  applies_when: { "all" => [issuer, { "field" => "doc.issuer.tax_regime", "op" => "neq", "value" => "unknown" }] },
  assert: { "any" => [
    { "all" => [simples, { "field" => "doc.issuer.tax_regime", "op" => "in", "value" => %w[simples_nacional simples_nacional_excess mei] }] },
    { "all" => [normal_regime, { "field" => "doc.issuer.tax_regime", "op" => "eq", "value" => "normal" }] }
  ] },
  message: "A nota declara CRT {{doc.issuer.crt}} ({{doc.issuer.tax_regime}}), mas o cenário do cliente é {{scenario.tax_regime}}. Revise o cenário ou o cadastro no ERP.")

seed_rule!("CFOP.SCOPE.MATCH", title: "CFOP × âmbito da operação (idDest)", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[cfop],
  applies_when: { "all" => [issuer, { "field" => "doc.operation.scope", "op" => "present" }] },
  assert: { "field" => "item.cfop_scope", "op" => "eq", "value" => { "ref" => "doc.operation.scope" } },
  message: "CFOP {{item.product.cfop}} é de operação {{item.cfop_scope}}, mas a nota indica operação {{doc.operation.scope}} (idDest).",
  group_by: ["item.product.cfop", "doc.operation.scope"])

seed_rule!("CFOP.KNOWN", title: "CFOP inexistente na tabela vigente", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[cfop],
  applies_when: { "field" => "item.cfop_known", "op" => "present" },
  assert: { "field" => "item.cfop_known", "op" => "eq", "value" => true },
  message: "CFOP {{item.product.cfop}} não existe na tabela vigente na data de emissão.",
  group_by: ["item.product.cfop"])

seed_rule!("DOC.RETURN.REFERENCE", title: "Devolução sem nota referenciada", scope: "document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[return],
  applies_when: { "all" => [issuer, { "field" => "doc.issuance.purpose", "op" => "eq", "value" => "return" }] },
  assert: { "some" => "doc.references", "as" => "r", "where" => { "field" => "r.access_key", "op" => "present" } },
  message: "Nota de devolução (finNFe=4) sem chave de NF-e referenciada.")

seed_rule!("DOC.TOTALS.ITEMS_SUM", title: "Totais da nota × soma dos itens", scope: "document", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[integrity],
  primitive: { "name" => "items_sum_matches_totals", "params" => { "fields" => %w[products icms_base icms icms_st ipi pis cofins], "tolerance" => "0.01" } },
  message: "Total {{field}} da nota ({{total}}) diverge da soma dos itens ({{items_sum}}).",
  group_by: ["field"])

seed_rule!("ICMS.AMOUNT.CALC", title: "vICMS ≠ vBC × alíquota", scope: "item", severity: "error", effective_from: Date.new(2010, 1, 1), tags: %w[icms],
  params: { "tolerance" => "0.02" },
  applies_when: { "all" => [{ "field" => "item.icms.expected_amount", "op" => "present" }, { "field" => "item.icms.amount", "op" => "present" }] },
  assert: { "field" => "item.icms.amount", "op" => "approx", "value" => { "ref" => "item.icms.expected_amount" }, "tolerance" => { "param" => "tolerance" } },
  message: "ICMS destacado {{item.icms.amount}} difere de base × alíquota = {{item.icms.expected_amount}}.")

seed_rule!("ICMS.RATE.INTERSTATE", title: "Alíquota interestadual de ICMS", scope: "item", severity: "error", effective_from: Date.new(2013, 1, 1), tags: %w[icms interstate],
  let: [{ "lookup" => "icms_interstate_rate", "key" => [{ "ref" => "doc.operation.origin_uf" }, { "ref" => "doc.operation.destination_uf" }, { "ref" => "item.icms.origin_category" }], "as" => "expected" }],
  applies_when: { "all" => [issuer, normal_regime, { "field" => "doc.operation.scope", "op" => "eq", "value" => "interstate" },
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
seed_rule!("IBSCBS.GROUP.REQUIRED", version: 2, title: "Grupo IBS/CBS ausente", scope: "item", severity: "error", effective_from: Date.new(2026, 8, 3), tags: %w[ibs_cbs reforma],
  applies_when: ibs_applies, assert: { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true },
  message: "Item sem grupo IBS/CBS em documento autorizado após 03/08/2026 — verifique a integridade do XML.",
  legal_references: [{ "label" => "NT 2025.002 v1.40" }])

seed_rule!("IBSCBS.CBS.RATE_SCHEDULE", title: "Alíquota CBS × cronograma do ano", scope: "item", severity: "error", effective_from: Date.new(2026, 1, 1), tags: %w[ibs_cbs reforma],
  applies_when: { "all" => [issuer, { "field" => "item.ibs_cbs.present", "op" => "eq", "value" => true }, { "field" => "item.ibs_cbs.cst", "op" => "eq", "value" => "000" },
                            { "field" => "item.ibs_cbs.cbs.rate", "op" => "present" }, { "field" => "item.ibs_cbs.schedule_rates.cbs", "op" => "present" }] },
  assert: { "field" => "item.ibs_cbs.cbs.rate", "op" => "approx", "value" => { "ref" => "item.ibs_cbs.schedule_rates.cbs" }, "tolerance" => "0.001" },
  message: "Alíquota CBS {{item.ibs_cbs.cbs.rate}}% diverge do cronograma vigente ({{item.ibs_cbs.schedule_rates.cbs}}%).",
  legal_references: [{ "label" => "LC 214/2025 art. 343" }],
  group_by: ["item.ibs_cbs.cbs.rate"])

puts "rules: #{Rules::Rule.count}"
