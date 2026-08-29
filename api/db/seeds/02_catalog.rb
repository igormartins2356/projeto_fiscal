def seed_table!(code, name:, key_names:, source_class:, effective_from:, rows:, legal_basis: nil, source_url: nil)
  table = Catalog::ReferenceTable.find_or_create_by!(code:) { |t| t.name = name; t.key_names = key_names; t.key_arity = key_names.size; t.source_class = source_class; t.source_url = source_url }
  return if table.versions.exists?
  version = table.versions.create!(version: 1, effective_from:, state: "published", published_at: Time.current, source_url:, notes: "seed inicial")
  Catalog::ReferenceRow.insert_all!(rows.map { |key, data| { reference_version_id: version.id, key: Array(key).map(&:to_s), data:, legal_basis: } })
  puts "catalog: #{code} (#{rows.size} rows)"
end

# CFOP — recorte; a tabela completa vem do importador (DATA_SOURCES.md §1.3). Colunas nature/direction são curadoria nossa.
cfop = {
  "1101" => "purchase", "1102" => "purchase", "1111" => "purchase", "1113" => "purchase", "1116" => "purchase", "1117" => "purchase",
  "1201" => "sale_return", "1202" => "sale_return", "1203" => "sale_return", "1204" => "sale_return", "1410" => "sale_return", "1411" => "sale_return",
  "1152" => "transfer", "1403" => "purchase", "1949" => "other",
  "2101" => "purchase", "2102" => "purchase", "2201" => "sale_return", "2202" => "sale_return", "2403" => "purchase", "2410" => "sale_return", "2411" => "sale_return", "2949" => "other",
  "3101" => "import", "3102" => "import",
  "5101" => "sale", "5102" => "sale", "5103" => "sale", "5104" => "sale", "5105" => "sale", "5106" => "sale", "5109" => "sale", "5110" => "sale", "5111" => "sale", "5112" => "sale",
  "5401" => "sale", "5403" => "sale", "5405" => "sale", "5152" => "transfer", "5201" => "purchase_return", "5202" => "purchase_return", "5410" => "purchase_return", "5411" => "purchase_return",
  "5910" => "bonus", "5911" => "bonus", "5912" => "demonstration", "5913" => "shipment_return", "5915" => "shipment", "5916" => "shipment_return", "5917" => "consignment", "5918" => "shipment_return", "5949" => "other",
  "6101" => "sale", "6102" => "sale", "6107" => "sale", "6108" => "sale", "6401" => "sale", "6403" => "sale", "6404" => "sale", "6152" => "transfer", "6201" => "purchase_return", "6202" => "purchase_return", "6410" => "purchase_return", "6411" => "purchase_return", "6910" => "bonus", "6949" => "other",
  "7101" => "export", "7102" => "export"
}
seed_table!("cfop", name: "CFOP", key_names: ["cfop"], source_class: "B", effective_from: Date.new(2024, 6, 1),
            source_url: "https://www.confaz.fazenda.gov.br/legislacao/ajustes/sinief/cfop_cvsn_70_vigente", legal_basis: "Ajuste SINIEF s/nº 1970, Anexo (Ajuste SINIEF 03/24)",
            rows: cfop.map { |c, n| [[c], { "nature" => n, "direction" => c.start_with?("1", "2", "3") ? "inbound" : "outbound", "st_related" => %w[5401 5403 5405 6401 6403 6404 1403 2403 5410 5411 6410 6411 1410 1411 2410 2411].include?(c) }] })

csosn = { "101" => "simples_with_credit", "102" => "simples_without_credit", "103" => "exempt", "201" => "simples_with_credit_st", "202" => "simples_without_credit_st",
          "203" => "exempt_st", "300" => "immune", "400" => "not_taxed", "500" => "st_withheld", "900" => "other" }
seed_table!("csosn", name: "CSOSN", key_names: ["csosn"], source_class: "D", effective_from: Date.new(2010, 1, 1), legal_basis: "Ajuste SINIEF 07/05, Tabela B",
            rows: csosn.map { |c, k| [[c], { "taxation_kind" => k, "regime" => "simples_nacional" }] })

cst_icms = { "00" => "taxed", "10" => "taxed_with_st", "20" => "reduced_base", "30" => "exempt_with_st", "40" => "exempt", "41" => "not_taxed", "50" => "suspended",
             "51" => "deferred", "60" => "st_withheld", "70" => "reduced_base_with_st", "90" => "other" }
seed_table!("cst_icms", name: "CST ICMS", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Ajuste SINIEF 07/05, Tabela B",
            rows: cst_icms.map { |c, k| [[c], { "taxation_kind" => k, "regime" => "normal" }] })

cst_pc = { "01" => "taxed", "02" => "taxed", "03" => "taxed", "04" => "single_phase", "05" => "st", "06" => "zero_rate", "07" => "exempt", "08" => "no_incidence", "09" => "suspended",
           "49" => "other", "50" => "taxed", "51" => "taxed", "52" => "taxed", "53" => "taxed", "54" => "taxed", "55" => "taxed", "56" => "taxed", "60" => "taxed", "70" => "other", "71" => "other", "72" => "other", "73" => "other", "74" => "other", "75" => "other", "98" => "other", "99" => "other" }
seed_table!("cst_pis_cofins", name: "CST PIS/COFINS", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Tabela 4.3.3 SPED",
            rows: cst_pc.map { |c, k| [[c], { "taxation_kind" => k }] })

# Cronograma IBS/CBS (DATA_SOURCES.md §1.11). 2027+ CBS é estimativa até a Resolução do Senado.
sched = [
  [["2026", "cbs"], { "rate" => "0.90", "kind" => "test" }], [["2026", "ibs_uf"], { "rate" => "0.10", "kind" => "test" }], [["2026", "ibs_city"], { "rate" => "0.00", "kind" => "test" }],
  [["2027", "cbs"], { "rate" => "9.21", "kind" => "estimated", "note" => "estimativa CGIBS 06/08/2026; aguardando Resolução do Senado" }],
  [["2027", "ibs_uf"], { "rate" => "0.05", "kind" => "test" }], [["2027", "ibs_city"], { "rate" => "0.05", "kind" => "test" }]
]
seed_table!("ibs_cbs_schedule", name: "Cronograma IBS/CBS", key_names: %w[year tax], source_class: "D", effective_from: Date.new(2026, 1, 1), legal_basis: "LC 214/2025 arts. 343-349", rows: sched)

# Alíquotas interestaduais (Res. Senado 22/89 e 13/2012): gerado a partir das regiões.
south_southeast = %w[SP RJ MG RS SC PR] # ES fica de fora (destino recebe 12%)
ufs = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO]
inter = []
ufs.each do |o|
  ufs.each do |d|
    next if o == d
    rate = south_southeast.include?(o) && !south_southeast.include?(d) ? "7.00" : "12.00"
    inter << [[o, d, "domestic"], { "rate" => rate }]
    inter << [[o, d, "imported"], { "rate" => "4.00" }]
  end
end
seed_table!("icms_interstate_rate", name: "Alíquota interestadual ICMS", key_names: %w[origin_uf destination_uf origin_category], source_class: "D", effective_from: Date.new(2013, 1, 1),
            legal_basis: "Resolução Senado 22/1989; Resolução Senado 13/2012", rows: inter)

# Alíquota interna geral por UF ("*" = geral) — recorte Sudeste; demais UFs entram na curadoria (DATA_SOURCES.md §1.6).
internal = { "SP" => ["18.00", "0.00"], "MG" => ["18.00", "2.00"], "RJ" => ["20.00", "2.00"], "ES" => ["17.00", "0.00"] }
seed_table!("icms_internal_rate", name: "Alíquota interna ICMS", key_names: %w[uf ncm], source_class: "C", effective_from: Date.new(2024, 1, 1),
            legal_basis: "Lei estadual do ICMS de cada UF (verificar por linha)", rows: internal.map { |uf, (r, fcp)| [[uf, "*"], { "rate" => r, "fcp_rate" => fcp }] })
