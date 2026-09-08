load Rails.root.join("db/seeds/00_helpers.rb") unless respond_to?(:seed_table!, true)
# Leiaute COMPLETO da EFD ICMS/IPI extraído do Guia Prático v3.2.3 (leiaute 020) — db/data/sped_layout_020.json (263 registros).
# Campos duplicados no Guia (ex.: C170 tem ALIQ_PIS % e ALIQ_PIS em reais) recebem sufixo _2.
raw = JSON.parse(File.read(Rails.root.join("db/data/sped_layout_020.json")))
DOC_KEY_FIELDS = %w[CHV_NFE CHV_CTE CHV_DFE CHV_DOCE CHV_NFE_CTE].freeze

rows = raw["records"].map do |rec, spec|
  seen = Hash.new(0)
  fields = spec["fields"].map { |f| seen[f] += 1; seen[f] > 1 ? "#{f}_#{seen[f]}" : f }
  [[rec], { "fields" => fields, "required" => spec["required"], "level" => spec["level"],
            "doc_key_field" => (fields & DOC_KEY_FIELDS).first, "identifies_document" => fields.include?("CHV_NFE") }]
end

table = Catalog::ReferenceTable.find_or_create_by!(code: "sped_layout") { |t| t.name = "Leiaute EFD ICMS/IPI"; t.key_names = ["record"]; t.key_arity = 1; t.source_class = "B"; t.source_url = "https://www.gov.br/sped/pt-br/assuntos/escrituracoes-digitais/efd-icms-ipi/manuais-e-documentos-tecnicos" }
# Substitui versões anteriores (a v1 manual tinha o C100 desalinhado a partir do campo 17 — faltava IND_FRT)
if table.versions.none? { |v| v.notes.to_s.include?("guia-3.2.3-completo") }
  table.versions.destroy_all
  [[1, Date.new(2012, 1, 1), "guia-3.2.3-completo aplicado retroativamente (leiautes antigos: importar Guia da época se precisar de precisão histórica)"],
   [2, Date.new(2026, 1, 1), "guia-3.2.3-completo — leiaute 020 oficial (Ato COTEPE 44/2018; NT 2025.001)"]].each do |version, from, note|
    v = table.versions.create!(version:, effective_from: from, effective_until: (version == 1 ? Date.new(2025, 12, 31) : nil), state: "draft",
                               notes: note, source_url: table.source_url)
    Catalog::ReferenceRow.insert_all!(rows.map { |key, data| { reference_version_id: v.id, key:, data:, legal_basis: "Guia Prático EFD-ICMS/IPI v3.2.3 / Ato COTEPE 44/2018" } })
    v.update!(state: "published", published_at: Time.current)
  end
  puts "sped_layout: #{rows.size} registros (v1 2012–2025, v2 2026+)"
end
