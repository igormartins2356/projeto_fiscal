load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true) && respond_to?(:seed_rule!, true)
# Complementos de catálogo exigidos pela base completa de regras (idempotente: atualiza linhas existentes).

# CFOP: papel na ST (substitute = vende com ST retendo; substituted = mercadoria com ST já retida; none) e se exige nota referenciada
ST_SUBSTITUTE = %w[5401 5402 5403 6401 6402 6403 6404? 5410 5411 6410 6411 1401 1403 2401 2403].freeze
ST_ROLES = {
  "substitute" => %w[5401 5402 5403 6401 6402 6403 5410 5411 6410 6411 1401 1403 2401 2403 1410 1411 2410 2411],
  "substituted" => %w[5405 6404 5656 6656 1653 2653]
}.freeze
REQUIRES_REF = %w[1201 1202 1203 1204 1410 1411 2201 2202 2410 2411 5201 5202 5410 5411 6201 6202 6410 6411].freeze
cfop_table = Catalog::ReferenceTable.find_by(code: "cfop")
if cfop_table
  extra = { "5405" => "sale", "6404" => "sale", "5402" => "sale", "6402" => "sale", "5656" => "sale", "6656" => "sale", "1653" => "purchase", "2653" => "purchase",
            "5117" => "sale", "6117" => "sale", "5118" => "sale", "5119" => "sale", "5120" => "sale", "5122" => "sale", "5123" => "sale", "5124" => "industrialization", "5125" => "industrialization",
            "5901" => "shipment", "5902" => "shipment_return", "5903" => "shipment_return", "5904" => "shipment", "5905" => "shipment", "5906" => "shipment_return", "5907" => "shipment_return", "5908" => "shipment", "5909" => "shipment_return",
            "5920" => "shipment", "5921" => "shipment", "5922" => "other", "5923" => "shipment", "5924" => "shipment", "5925" => "shipment_return", "5926" => "other", "5927" => "other", "5928" => "other", "5929" => "other",
            "6901" => "shipment", "6902" => "shipment_return", "6905" => "shipment", "6906" => "shipment_return", "6910" => "bonus", "6911" => "bonus", "6912" => "demonstration", "6913" => "shipment_return", "6915" => "shipment", "6916" => "shipment_return", "6917" => "consignment", "6918" => "shipment_return", "6920" => "shipment", "6949" => "other",
            "1901" => "shipment_return", "1902" => "shipment_return", "1903" => "shipment", "1904" => "shipment", "1905" => "shipment", "1906" => "shipment", "1908" => "shipment", "1909" => "shipment", "1910" => "bonus", "1911" => "bonus", "1912" => "demonstration", "1913" => "shipment_return", "1915" => "shipment", "1916" => "shipment_return", "1917" => "consignment", "1918" => "shipment_return", "1949" => "other",
            "2901" => "shipment_return", "2902" => "shipment_return", "2910" => "bonus", "2911" => "bonus", "2912" => "demonstration", "2913" => "shipment_return", "2915" => "shipment", "2916" => "shipment_return", "2949" => "other",
            "1124" => "industrialization", "1125" => "industrialization", "2124" => "industrialization", "2125" => "industrialization", "1126" => "purchase", "1401" => "purchase", "2401" => "purchase",
            "5501" => "sale", "5502" => "sale", "6501" => "sale", "6502" => "sale", "7101" => "export", "7102" => "export", "7127" => "export", "7949" => "other", "3101" => "import", "3102" => "import", "3949" => "other" }
  cfop_table.versions.find_each do |v|
    existing = v.rows.pluck(:key).map(&:first)
    extra.each do |code, nature|
      next if existing.include?(code)
      v.rows.create!(key: [code], data: { "nature" => nature, "direction" => code.start_with?("1", "2", "3") ? "inbound" : "outbound", "st_related" => false }, legal_basis: "Ajuste SINIEF s/nº 1970, Anexo")
    end
    v.rows.find_each do |r|
      code = r.key.first
      role = ST_ROLES.find { |_, codes| codes.include?(code) }&.first || "none"
      data = r.data.merge("st_role" => role, "st_related" => role != "none", "requires_reference" => REQUIRES_REF.include?(code),
                          "own_production" => %w[5101 6101 7101 5401 6401 5501 6501 5124 5125].include?(code))
      r.update!(data:) if data != r.data
    end
  end
  puts "catalog: cfop enriquecido (st_role, requires_reference, own_production)"
end

# CST IPI (Tabela 4.3.2 SPED): 00-49 entrada, 50-99 saída
cst_ipi = { "00" => %w[inbound taxed], "01" => %w[inbound taxed], "02" => %w[inbound exempt], "03" => %w[inbound exempt], "04" => %w[inbound immune], "05" => %w[inbound suspended],
            "49" => %w[inbound other], "50" => %w[outbound taxed], "51" => %w[outbound taxed], "52" => %w[outbound exempt], "53" => %w[outbound not_taxed], "54" => %w[outbound immune], "55" => %w[outbound suspended], "99" => %w[outbound other] }
seed_table!("cst_ipi", name: "CST IPI", key_names: ["cst"], source_class: "D", effective_from: Date.new(2000, 1, 1), legal_basis: "Tabela 4.3.2 SPED / IN RFB 1.009/2010",
            rows: cst_ipi.map { |c, (dir, kind)| [[c], { "direction" => dir, "taxation_kind" => kind }] })

# Direção do CST PIS/COFINS (01-49 saída, 50-99 entrada) — complementa cst_pis_cofins
pc_table = Catalog::ReferenceTable.find_by(code: "cst_pis_cofins")
pc_table&.versions&.find_each do |v|
  v.rows.find_each do |r|
    dir = r.key.first.to_i <= 49 ? "outbound" : "inbound"
    r.update!(data: r.data.merge("direction" => dir)) unless r.data["direction"] == dir
  end
end

# Cronograma IBS/CBS: alíquota-teste de IBS municipal em 2026 é 0 (o 0,1% é estadual). Já está no seed principal.

# Tabelas previstas em DATA_SOURCES.md ainda sem importação: registradas sem versão (lookup estrito vira evaluation_error até publicar).
[["tipi", "TIPI — alíquotas de IPI por NCM", ["ncm"], "B", "https://www.gov.br/receitafederal/pt-br/assuntos/orientacao-tributaria/ipi"],
 ["pis_cofins_special", "PIS/COFINS — NCM monofásicos, alíquota zero, suspensão", ["ncm"], "B", "https://www.gov.br/sped/pt-br"],
 ["ibs_cbs_class", "Classificação tributária IBS/CBS (cClassTrib)", ["class_code"], "A", "https://dfe-portal.svrs.rs.gov.br/DFE/ClassificacaoTributaria"],
 ["cest", "CEST por NCM (Convênio ICMS 142/18)", ["ncm"], "B", "https://www.confaz.fazenda.gov.br/legislacao/convenios/2018/CV142_18"],
 ["st_uf", "NCM/CEST sujeitos a ST por UF", %w[uf code], "C", nil],
 ["ncm", "NCM", ["ncm"], "A", "https://portalunico.siscomex.gov.br/classif/api/publico/nomenclatura/download/json?perfil=PUBLICO"]].each do |code, name, keys, klass, url|
  Catalog::ReferenceTable.find_or_create_by!(code:) { |t| t.name = name; t.key_names = keys; t.key_arity = keys.size; t.source_class = klass; t.source_url = url; t.next_review_on = Date.current }
end
puts "catalog: tabelas pendentes registradas"

# correção 30/08: FCP geral de MG = 0 (FCP mineiro só em produtos específicos)
Catalog::ReferenceRow.joins(reference_version: :reference_table).where(reference_tables: { code: "icms_internal_rate" }).where("key = ARRAY['MG','*']::varchar[]").find_each { |r| r.update!(data: r.data.merge("fcp_rate" => "0.00")) if r.data["fcp_rate"] != "0.00" }

# cadência de revisão por classe (DATA_SOURCES.md §3): A=sincronização automática; B=mensal; C=trimestral; D=anual
{"A" => 90, "B" => 30, "C" => 90, "D" => 365}.each do |klass, days|
  Catalog::ReferenceTable.where(source_class: klass).where(next_review_on: nil).update_all(next_review_on: Date.current + days)
end
