# Cliente de teste do cross-check SPED: IRMAOS DZENKAUSKAS LTDA (Victor Dzenk) — confecção, Lagoa Santa/MG, não optante do Simples.
firm = Accounts::Firm.find_by!(name: "Escritório Piloto")
client = Accounts::Client.find_or_create_by!(firm:, cnpj: "66412974000190") do |c|
  c.legal_name = "IRMAOS DZENKAUSKAS LTDA"
  c.trade_name = "VICTOR DZENK"
  c.uf = "MG"
  c.city_code = "3137601"
  c.ie = "3767884370084"
end
unless client.tax_scenarios.exists?
  client.tax_scenarios.create!(
    effective_from: Date.new(2026, 1, 1), state: "draft", created_by: Accounts::User.find_by!(email: "admin@fiscal.local"),
    data: { "tax_regime" => "lucro_presumido", "uf" => "MG", "city_code" => "3137601", "icms_taxpayer" => true, "ipi_taxpayer" => true,
            "iss_taxpayer" => false, "activity" => %w[industry commerce], "cnae" => { "primary" => "1412601", "secondary" => [] },
            "sells_to_final_consumer" => true, "uses_nfce" => false, "exports" => false, "imports" => false,
            "st" => { "source" => "catalog", "applies" => false, "overrides" => [] }, "benefits" => [],
            "pis_cofins" => { "regime" => "cumulative" }, "ibs_cbs" => { "regime" => "regular" },
            "notes" => "Matriz (aberta 1991). Não optante do Simples (cnpj_ws). Confecção de vestuário (CNAE 1412-6/01) → indústria: contribuinte de IPI (vestuário majoritariamente alíquota 0 na TIPI). Regime presumido como Lucro Presumido — CONFIRMAR com o contador (usar as notas/EFD para inferir). Cliente destinado ao teste do cross-check SPED." },
    field_origins: Hash[%w[tax_regime uf city_code icms_taxpayer ipi_taxpayer activity cnae sells_to_final_consumer uses_nfce exports imports st pis_cofins ibs_cbs].map { |k| [k, "manual"] }]
  )
end
puts "dzenk: client=#{client.id} scenarios=#{client.tax_scenarios.count}"
