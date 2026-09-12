namespace :sefaz do
  desc "Atualiza a documentação oficial da NF-e/NFC-e em storage/sefaz (rake 'sefaz:sync[notas_tecnicas]')"
  task :sync, %i[sections] => :environment do |_t, args|
    sections = args[:sections].presence&.split(/[,\s]+/) || Sefaz::DocumentSync::SECTIONS.keys
    result = Sefaz::DocumentSync.new(sections:).call

    result.sections.each { |secao, n| puts "#{secao}: #{n} documentos listados" }
    puts result.to_s
    result.added.each   { |d| puts "  novo:     #{d}" }
    result.changed.each { |d| puts "  alterado: #{d}" }
    result.failed.each  { |f| puts "  FALHA:    #{f['documento']} — #{f['erro']}" }
    puts "manifesto: db/data/sefaz/manifest.json (versionado); arquivos: storage/sefaz (fora do git)"
  end

  desc "Lista o que há no manifesto, por seção"
  task inventory: :environment do
    path = Rails.root.join("db/data/sefaz/manifest.json")
    abort "sem manifesto: rode rake sefaz:sync" unless File.exist?(path)
    manifest = JSON.parse(File.read(path))
    por_secao = manifest["documentos"].values.group_by { |d| d["secao"] }
    puts "sincronizado em #{manifest['sincronizado_em']}"
    por_secao.sort.each do |secao, docs|
      bytes = docs.sum { |d| d["bytes"].to_i }
      recentes = docs.filter_map { |d| d["publicado_em"] }.max
      puts format("%-20s %4d documentos  %8.1f MiB  mais recente: %s", secao, docs.size, bytes / 1048576.0, recentes || "—")
    end
    puts "total: #{manifest['documentos'].size} documentos"
  end
end
