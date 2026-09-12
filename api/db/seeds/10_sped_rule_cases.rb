require Rails.root.join("lib/rule_case_builder")
load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_rule!, true)
B = RuleCaseBuilder unless defined?(B)
# Cenário dos casos SPED: cross-check XML × EFD independe de regime, mas o cenário é obrigatório no caso de teste.
PRESUMIDO_SP = { "tax_regime" => "lucro_presumido", "uf" => "SP", "icms_taxpayer" => true, "activity" => ["commerce"], "pis_cofins" => { "regime" => "cumulative" } } unless defined?(PRESUMIDO_SP)

def sped_cases!(code, fire:, pass:)
  rule = Rules::Rule.where(code:).order(version: :desc).first or (puts "  ! #{code}"; return)
  return if rule.test_cases.exists?
  fire.each { |(name, input)| rule.test_cases.create!(name: "dispara: #{name}", reference_date: "2026-07-31", scenario: PRESUMIDO_SP, catalog: {}, input:, expect: { "findings" => [{ "severity" => rule.severity }] }) }
  pass.each { |(name, input)| rule.test_cases.create!(name: "não dispara: #{name}", reference_date: "2026-07-31", scenario: PRESUMIDO_SP, catalog: {}, input:, expect: { "findings" => [] }) }
end

# caso avulso, idempotente pelo nome (a regra já tem casos; sped_cases! só cria o lote inicial)
def sped_case!(code, name, input, expect)
  rule = Rules::Rule.where(code:).order(version: :desc).first or (puts "  ! #{code}"; return)
  return if rule.test_cases.exists?(name:)
  rule.test_cases.create!(name:, reference_date: "2026-07-31", scenario: PRESUMIDO_SP, catalog: {}, input:, expect:)
end

def key_for2(n) = "35260712345678000190550010000#{n.to_s.rjust(6, '0')}1000#{n.to_s.rjust(6, '0')}"
doc = B.doc(normal: true, doc: { "access_key" => key_for2(100), "issuance" => { "number" => 100, "issued_at" => "2026-07-10T10:00:00-03:00" } })
cancelled = B.doc(normal: true, doc: { "access_key" => key_for2(101), "issuance" => { "number" => 101, "issued_at" => "2026-07-11T10:00:00-03:00" }, "status" => { "state" => "cancelled" } })

def c100(key, number, over_fields = {}, c170: [], c190: [])
  { "record_id" => 1000 + number, "line" => 10 + number, "access_key" => key,
    "fields" => { "IND_OPER" => "1", "IND_EMIT" => "0", "COD_MOD" => "55", "COD_SIT" => "00", "SER" => "1", "NUM_DOC" => number.to_s, "CHV_NFE" => key,
                  "VL_DOC" => "1000.00", "VL_DESC" => "0.00", "VL_MERC" => "1000.00", "VL_BC_ICMS" => "1000.00", "VL_ICMS" => "180.00", "VL_IPI" => "0.00",
                  "VL_PIS" => "6.50", "VL_COFINS" => "30.00", "VL_BC_ICMS_ST" => "0.00", "VL_ICMS_ST" => "0.00" }.merge(over_fields),
    "c170" => c170, "c190" => c190 }
end
def c170_row(over = {})
  { "record_id" => 2001, "line" => 21, "fields" => { "NUM_ITEM" => "1", "COD_ITEM" => "A1", "QTD" => "2.0000", "VL_ITEM" => "1000.00", "VL_DESC" => "0.00",
                                                     "CST_ICMS" => "000", "CFOP" => "5102", "VL_BC_ICMS" => "1000.00", "ALIQ_ICMS" => "18.00", "VL_ICMS" => "180.00" }.merge(over) }
end
def c190_row(over = {})
  { "record_id" => 3001, "line" => 31, "fields" => { "CST_ICMS" => "000", "CFOP" => "5102", "ALIQ_ICMS" => "18.00", "VL_OPR" => "1000.00", "VL_BC_ICMS" => "1000.00", "VL_ICMS" => "180.00", "VL_BC_ICMS_ST" => "0.00", "VL_ICMS_ST" => "0.00", "VL_RED_BC" => "0.00", "VL_IPI" => "0.00" }.merge(over) }
end
file = ->(c100s, errors: []) { { "info" => { "id" => 1, "errors" => errors }, "c100" => c100s } }
inp = ->(docs, f) { { "kind" => "canonical", "documents" => docs, "monitored_cnpj" => "12345678000190", "fiscal_file" => f } }

sped_cases!("SPED.DOC.MISSING_IN_FILE",
  fire: [["nota fora do arquivo", inp.([doc], file.([]))], ["C100 sem XML", inp.([doc], file.([c100(key_for2(100), 100), c100(key_for2(999), 999)]))]],
  pass: [["conciliado", inp.([doc], file.([c100(key_for2(100), 100)]))]])
sped_cases!("SPED.DOC.CANCELLED_SIT",
  fire: [["cancelada como regular", inp.([doc, cancelled], file.([c100(key_for2(100), 100), c100(key_for2(101), 101)]))],
         ["cancelada ausente", inp.([doc, cancelled], file.([c100(key_for2(100), 100)]))]],
  pass: [["cancelada com COD_SIT 02", inp.([doc, cancelled], file.([c100(key_for2(100), 100), c100(key_for2(101), 101, { "COD_SIT" => "02" })]))]])
sped_cases!("SPED.DOC.VALUES",
  fire: [["VL_ICMS divergente", inp.([doc], file.([c100(key_for2(100), 100, { "VL_ICMS" => "150.00" })]))]],
  pass: [["totais iguais", inp.([doc], file.([c100(key_for2(100), 100)]))]])
sped_cases!("SPED.ITEM.MISMATCH",
  fire: [["CFOP divergente no item", inp.([doc], file.([c100(key_for2(100), 100, {}, c170: [c170_row("CFOP" => "5405")])]))],
         ["CST com origem divergente", inp.([doc], file.([c100(key_for2(100), 100, {}, c170: [c170_row("CST_ICMS" => "060")])]))]],
  pass: [["item espelhado", inp.([doc], file.([c100(key_for2(100), 100, {}, c170: [c170_row])]))]])
sped_cases!("SPED.C190.CONSISTENCY",
  fire: [["C190 não soma os C170", inp.([doc], file.([c100(key_for2(100), 100, {}, c170: [c170_row], c190: [c190_row("VL_ICMS" => "100.00")])]))]],
  pass: [["C190 consolida", inp.([doc], file.([c100(key_for2(100), 100, {}, c170: [c170_row], c190: [c190_row])]))]])
sped_cases!("SPED.DOC.NO_ANALYTIC",
  fire: [["C100 regular sem C190", inp.([doc], file.([c100(key_for2(100), 100)]))]],
  pass: [["com C190", inp.([doc], file.([c100(key_for2(100), 100, {}, c190: [c190_row])]))], ["cancelada sem filhos", inp.([doc, cancelled], file.([c100(key_for2(100), 100, {}, c190: [c190_row]), c100(key_for2(101), 101, { "COD_SIT" => "02" })]))]])
sped_cases!("SPED.STRUCTURE",
  fire: [["erro do parser", inp.([doc], file.([], errors: [{ "line" => 1, "record" => "0000", "error" => "CNPJ do arquivo difere do cliente" }]))]],
  pass: [["sem erros", inp.([doc], file.([]))]])

# NF-e de emissão própria pode ser de ENTRADA (devolução/retorno de industrialização): o C100 tem IND_EMIT=0
# e o XML existe na base como inbound — não pode ser apontado como "C100 sem XML".
entrada_propria = B.doc(normal: true, doc: { "access_key" => key_for2(102), "issuance" => { "number" => 102, "issued_at" => "2026-07-12T10:00:00-03:00" },
                                             "operation" => { "direction_declared" => "inbound", "nature_text" => "RETORNO DE INDUSTRIALIZACAO" } })
sped_case!("SPED.DOC.MISSING_IN_FILE", "não dispara: C100 de entrada de emissão própria com XML na base",
           inp.([doc, entrada_propria], file.([c100(key_for2(100), 100), c100(key_for2(102), 102, { "IND_OPER" => "0" })])), { "findings" => [] })

puts "sped cases: #{Rules::RuleTestCase.joins(:rule).where(rules: { code: Rules::Rule.where("code LIKE 'SPED.%'").select(:code) }).count}"
