# Helpers compartilhados pelas seeds (carregado primeiro por ordem alfabética; seeds isoladas fazem load explícito)
# Pré-go-live (development/test) as seeds são a fonte de verdade e podem sobrescrever o publicado; em qualquer outro ambiente publicado é imutável.
def seed_pre_golive_env? = Rails.env.development? || Rails.env.test?

# Escreve linhas numa versão. Versão publicada é imutável (findings e audit_runs.snapshot apontam para ela): fora de dev/test recusa; em dev/test avisa.
def seed_rows!(version, rows, legal_basis: nil)
  if version.state == "published"
    msg = "tabela #{version.reference_table.code} v#{version.version} publicada: crie uma nova versão em vez de escrever linhas nela"
    raise msg unless seed_pre_golive_env?
    warn "seed_rows!: #{msg} (escrevendo mesmo assim em #{Rails.env})"
  end
  Catalog::ReferenceRow.insert_all!(rows.map { |key, data| { reference_version_id: version.id, key: Array(key).map(&:to_s), data:, legal_basis: } })
end

def seed_table!(code, name:, key_names:, source_class:, effective_from:, rows:, legal_basis: nil, source_url: nil)
  table = Catalog::ReferenceTable.find_or_create_by!(code:) { |t| t.name = name; t.key_names = key_names; t.key_arity = key_names.size; t.source_class = source_class; t.source_url = source_url }
  return refresh_seeded_version!(table, rows, effective_from:, legal_basis:) if table.versions.exists?
  # linhas entram em draft e só então a versão é publicada
  version = table.versions.create!(version: 1, effective_from:, state: "draft", source_url:, notes: "seed inicial")
  seed_rows!(version, rows, legal_basis:)
  version.update!(state: "published", published_at: Time.current)
  puts "catalog: #{code} (#{rows.size} rows)"
end

# Banco já semeado: pré-go-live a seed é a fonte da v1 que ela própria criou, então curadoria nova (linha corrigida,
# coluna nova, vigência) reescreve essa v1 em dev/test, avisando. Sem isso o banco ficava com a tabela antiga em
# silêncio — a seed era ignorada e só um db:reset aplicava a mudança.
# A seed NUNCA toca em versão que não é dela: se existe v2 (importação pelo painel, curadoria) ou a v1 foi editada,
# só avisa — sobrescrever apagaria dado curado que não está no repositório.
# Fora de dev/test a versão publicada é imutável (findings e audit_runs.snapshot apontam para ela): a atualização é uma versão nova.
def refresh_seeded_version!(table, rows, effective_from:, legal_basis: nil)
  version = table.versions.find_by(version: 1, notes: "seed inicial")
  if version.nil? || table.versions.where("version > 1").exists?
    puts "catalog: #{table.code} tem versão fora do controle da seed — não reescrita (db:reset para recarregar a v1)"
    return
  end
  desired = rows.to_h { |key, data| [Array(key).map(&:to_s), data.as_json] }
  return if version.effective_from == effective_from && version.rows.pluck(:key, :data).to_h == desired

  msg = "tabela #{table.code} v1 #{version.state}: o conteúdo da seed difere do que está no banco — crie uma nova versão"
  raise msg unless seed_pre_golive_env?
  warn "seed_table!: #{msg} (reescrevendo em #{Rails.env})"
  version.rows.delete_all
  version.update!(effective_from:)
  Catalog::ReferenceRow.insert_all!(desired.map { |key, data| { reference_version_id: version.id, key:, data:, legal_basis: } })
  puts "catalog: #{table.code} (#{rows.size} rows, reescrita)"
end

def seed_rule!(code, **attrs)
  body = attrs.extract!(:let, :applies_when, :assert, :primitive, :message, :explanation, :legal_references, :params, :group_by, :suggested_fix).compact.transform_keys(&:to_s)
  rule = Rules::Rule.find_or_initialize_by(code:, version: attrs.fetch(:version, 1))
  attrs = attrs.merge(body:, state: "published", published_at: rule.published_at || Time.current, source_type: "platform")
  # Regra publicada é imutável (findings apontam para a definição que os gerou): fora de dev/test exige versão nova; pré-go-live as seeds sobrescrevem, avisando.
  if rule.persisted? && rule.state == "published" && published_definition_changed?(rule, attrs)
    msg = "regra #{code} v#{rule.version} publicada: crie versão #{rule.version + 1}"
    raise msg unless seed_pre_golive_env?
    warn "seed_rule!: #{msg} (sobrescrevendo em #{Rails.env})"
  end
  rule.assign_attributes(attrs)
  rule.save!
  rule
end

def published_definition_changed?(rule, attrs)
  %i[body severity effective_from effective_until title scope].any? { |k| attrs.key?(k) && rule.public_send(k).as_json != attrs[k].as_json }
end

# Retirar fecha a vigência e muda o estado; título e corpo continuam como estavam quando os findings foram emitidos
# (regra publicada é imutável). `on:` é a data da decisão — vigência não pode depender do dia em que a seed rodou.
def retire_rule!(code, reason, on:)
  Rules::Rule.where(code:).where.not(state: "retired").find_each do |r|
    r.update!(state: "retired", effective_until: [r.effective_from, on].max)
    puts "rules: #{code} v#{r.version} retirada em #{on} — #{reason}"
  end
end

# Regime do cenário por tributo (LC 123/2006 arts. 13, 19 e 20; MOC/NT NF-e: CRT 1 e 4 informam CSOSN, CRT 2 e 3 informam CST).
# CRT 2 (excesso de sublimite) recolhe ICMS/ISS FORA do Simples — tributa o ICMS como regime normal —, mas
# PIS/COFINS/IPI continuam no DAS. MEI (CRT 4) é optante para todos os efeitos. Usado por 03/04/05 para não
# tratar `mei`/`simples_nacional_excess` como "não Simples" (falso positivo) nem como Simples no ICMS (falso negativo).
def simples_icms_regimes = %w[simples_nacional mei]
def normal_icms_regimes = %w[lucro_presumido lucro_real simples_nacional_excess]
def simples_federal_regimes = %w[simples_nacional simples_nacional_excess mei]
def normal_federal_regimes = %w[lucro_presumido lucro_real]
def regime_in(list) = { "field" => "scenario.tax_regime", "op" => "in", "value" => list }
