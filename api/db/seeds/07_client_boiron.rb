# Cliente real de teste: BOIRON MEDICAMENTOS HOMEOPATICOS LTDA. (filial 0004)
# Idempotente: find_or_create_by por firm + cnpj; cenário fica em draft (não publicar).
# Cliente de teste só existe em development/test (em produção os clientes vêm do cadastro da firma).
# A base foi zerada em 10/09/2026 para o cadastro de clientes reais: estes dois só voltam sob pedido
# explícito (SEED_TEST_CLIENTS=1), para um `db:seed` não recriá-los junto com o catálogo e as regras.
return unless (Rails.env.development? || Rails.env.test?) && ENV["SEED_TEST_CLIENTS"] == "1"
firm = Accounts::Firm.find_by!(name: "Escritório Piloto")
admin = Accounts::User.find_by!(email: "admin@fiscal.local")

client = Accounts::Client.find_or_create_by!(firm:, cnpj: "07498711000420") do |c|
  c.legal_name = "BOIRON MEDICAMENTOS HOMEOPATICOS LTDA."
  c.trade_name = nil
  c.uf = "SP"
  c.city_code = "3505708"
  c.ie = "153781540111" # IE ativa de SP (a 118694900111 está inativa)
  c.active = true
end

# Inscrições estaduais como substituto tributário (IE-ST) fora de SP.
ie_st = [
  { "uf" => "BA", "number" => "160907360" },
  { "uf" => "ES", "number" => "000083470" },
  { "uf" => "MA", "number" => "128652691" },
  { "uf" => "MG", "number" => "0015395420185" },
  { "uf" => "MT", "number" => "00139398236" },
  { "uf" => "PB", "number" => "169037096" },
  { "uf" => "PE", "number" => "118471589" },
  { "uf" => "PR", "number" => "0990831076" },
  { "uf" => "RJ", "number" => "11457959" },
  { "uf" => "RS", "number" => "9000069390" }
]

data = {
  "tax_regime" => "lucro_real",
  "uf" => "SP",
  "city_code" => "3505708",
  "icms_taxpayer" => true,
  "ipi_taxpayer" => false,
  "iss_taxpayer" => false,
  "activity" => ["commerce"],
  "cnae" => { "primary" => "4771703", "secondary" => [] },
  "sells_to_final_consumer" => false,
  "uses_nfce" => false,
  "exports" => false,
  "imports" => true,
  # IE-ST em 10 UFs: o cliente opera com ST (sem isso SCENARIO.ST.DISAGREEMENT nunca avalia o cenário)
  "st" => { "source" => "catalog", "applies" => true, "overrides" => [] },
  "benefits" => [],
  "pis_cofins" => { "regime" => "non_cumulative" },
  "ibs_cbs" => { "regime" => "regular" },
  "ie_st" => ie_st,
  "notes" => "Filial (matriz 07498711/0001). Não optante do Simples (cnpj_ws: simples=null). " \
             "Regime presumido como Lucro Real (medicamentos: PIS/COFINS monofásico, Lei 10.147/00) — CONFIRMAR com o contador. " \
             "Possui inscrições estaduais como substituto tributário em BA, ES, MA, MG, MT, PB, PE, PR, RJ, RS (IE-ST) → " \
             "vendas interestaduais com retenção de ICMS-ST de medicamentos. " \
             "CNAE 4771-7/03 comércio varejista de produtos farmacêuticos homeopáticos. Aberta em 31/10/2017."
}

scenario = Scenario::TaxScenario.find_or_create_by!(client:, effective_from: Date.new(2026, 1, 1)) do |s|
  s.state = "draft"
  s.created_by = admin
  s.data = data
  s.field_origins = data.keys.index_with { "manual" }
end

puts "boiron: client=#{client.id} scenario=#{scenario.id} state=#{scenario.state}"
