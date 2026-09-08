# Helpers compartilhados pelas seeds (carregado primeiro por ordem alfabética; seeds isoladas fazem load explícito)
def seed_table!(code, name:, key_names:, source_class:, effective_from:, rows:, legal_basis: nil, source_url: nil)
  table = Catalog::ReferenceTable.find_or_create_by!(code:) { |t| t.name = name; t.key_names = key_names; t.key_arity = key_names.size; t.source_class = source_class; t.source_url = source_url }
  return if table.versions.exists?
  version = table.versions.create!(version: 1, effective_from:, state: "published", published_at: Time.current, source_url:, notes: "seed inicial")
  Catalog::ReferenceRow.insert_all!(rows.map { |key, data| { reference_version_id: version.id, key: Array(key).map(&:to_s), data:, legal_basis: } })
  puts "catalog: #{code} (#{rows.size} rows)"
end

def seed_rule!(code, **attrs)
  body = attrs.extract!(:let, :applies_when, :assert, :primitive, :message, :explanation, :legal_references, :params, :group_by, :suggested_fix).compact.transform_keys(&:to_s)
  rule = Rules::Rule.find_or_initialize_by(code:, version: attrs.fetch(:version, 1))
  # Antes do go-live as seeds são a fonte de verdade: atualizam a definição (regras publicadas em produção ganham nova versão, não edição).
  rule.assign_attributes(attrs.merge(body:, state: "published", published_at: rule.published_at || Time.current, source_type: "platform"))
  rule.save!
  rule
end

def retire_rule!(code, reason)
  Rules::Rule.where(code:).where.not(state: "retired").find_each { |r| r.update!(state: "retired", effective_until: [r.effective_from, Date.current].max, title: "[REMOVIDA] #{r.title} — #{reason}") }
end
