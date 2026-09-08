namespace :rules do
  desc "Roda todos os casos de teste de todas as regras e falha se algum não passar"
  task test: :environment do
    total = failed = 0
    Rules::Rule.where.not(state: "retired").includes(:test_cases).order(:code, :version).each do |rule|
      next if rule.test_cases.empty?
      Rules::TestRunner.new(rule).run_all.each do |r|
        total += 1
        next if r.passed
        failed += 1
        puts "FAIL #{rule.code} v#{rule.version} — #{r.test_case.name}"
        r.details.each { |d| puts "     #{d}" }
        r.errors.each { |e| puts "     erro: #{e[:error]}" }
        r.findings.each { |f| puts "     finding: #{f[:message]}" } if r.test_case.expect["findings"].blank?
      end
    end
    missing = Rules::Rule.where.not(state: "retired").where.missing(:test_cases).pluck(:code, :version)
    puts "casos: #{total}, falhas: #{failed}, regras sem caso: #{missing.size} #{missing.first(10).inspect}"
    abort("casos de teste falhando") if failed > 0
  end

  desc "Valida estaticamente todas as regras"
  task validate: :environment do
    bad = 0
    Rules::Rule.where.not(state: "retired").order(:code, :version).each do |rule|
      v = Rules::Validator.new(rule.definition)
      next if v.valid? && v.warnings.empty?
      bad += 1 unless v.errors.empty?
      puts "#{rule.code} v#{rule.version}: #{v.errors.map { |e| "ERRO #{e}" }.join('; ')} #{v.warnings.map { |w| "aviso #{w}" }.join('; ')}"
    end
    abort("regras inválidas") if bad > 0
    puts "todas as #{Rules::Rule.where.not(state: "retired").count} regras ativas válidas"
  end
end
