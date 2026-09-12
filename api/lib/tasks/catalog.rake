namespace :catalog do
  desc "Cria versão draft da alíquota interna de ICMS a partir de db/data/icms_internal_rate.yml"
  task :icms_internal_rate, %i[effective_from] => :environment do |_t, args|
    all = YAML.load_file(Rails.root.join("db/data/icms_internal_rate.yml"))
    table = Catalog::ReferenceTable.find_by!(code: "icms_internal_rate")
    # Linha não conferida em fonte primária fica fora: tabela esparsa não gera apontamento, alíquota
    # errada gera. Para incluir, confira a norma e remova a marca no YAML.
    pending = all.select { |r| r["confirm"] }.map { |r| r["uf"] }
    rows = all.reject { |r| r["confirm"] }

    version = nil
    Catalog::ReferenceVersion.transaction do
      last = table.versions.order(version: :desc).first
      # A versão substitui a publicada vigente e começa onde ela começa: cada linha carrega a própria
      # vigência, então herdar a data mais antiga das linhas faria a publicação aposentar o histórico.
      current = table.versions.published.order(:effective_from).last
      version = table.versions.create!(
        version: (last&.version || 0) + 1,
        effective_from: args[:effective_from].presence&.to_date || current&.effective_from || Date.current.beginning_of_year,
        state: "draft",
        notes: "#{rows.size} UFs conferidas em fonte primária, de db/data/icms_internal_rate.yml em " \
               "#{Date.current.iso8601}. Fora por falta de conferência (#{pending.size}): #{pending.join(', ')}."
      )
      Catalog::ReferenceRow.insert_all!(rows.map do |r|
        { reference_version_id: version.id, key: [r["uf"], "*"],
          data: { "rate" => r["rate"], "fcp_rate" => r["fcp_rate"] },
          effective_from: r["effective_from"], legal_basis: r["legal_basis"] }
      end)
    end

    puts "icms_internal_rate v#{version.version} (draft): #{version.rows.count} UFs conferidas"
    puts "fora, sem conferência em fonte primária (#{pending.size}): #{pending.join(', ')}" if pending.any?
    puts "publicar pelo painel, ou: bin/rails 'catalog:publish[icms_internal_rate,#{version.version}]'"
  end

  desc "Publica uma versão de tabela do catálogo: catalog:publish[codigo,versao]"
  task :publish, %i[code version] => :environment do |_t, args|
    table = Catalog::ReferenceTable.find_by!(code: args[:code])
    version = table.versions.find_by!(version: args[:version].to_i)
    abort "versão #{version.version} está #{version.state}, não draft" unless version.state == "draft"
    without_basis = version.rows.where(legal_basis: [nil, ""]).count
    abort "#{without_basis} linha(s) sem base legal" if without_basis.positive?

    Catalog::ReferenceVersion.transaction do
      table.versions.published.where.not(id: version.id).where("effective_from <= ?", version.effective_from).find_each do |prev|
        closing = version.effective_from - 1
        if closing >= prev.effective_from
          prev.update!(effective_until: [prev.effective_until, closing].compact.min)
        else
          prev.update!(state: "retired", effective_until: [prev.effective_until, prev.effective_from].compact.min)
        end
      end
      version.update!(state: "published", published_at: Time.current)
    end
    puts "#{table.code} v#{version.version} publicada (vigência a partir de #{version.effective_from})"
  end
end
