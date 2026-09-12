module Audit
  # Orquestra um AuditRun: resolve cenário, regras e catálogo por vigência (um contexto por intervalo em que
  # nada muda), roda o motor e persiste findings com estado herdado.
  class Runner
    # Só estado posto por decisão humana atravessa runs. "fixed" não: se o mesmo dedupe_key reapareceu,
    # o problema voltou e o apontamento tem de nascer aberto, não escondido como corrigido.
    INHERITED_STATES = %w[justified false_positive ignored].freeze

    def initialize(run) = @run = run

    def call
      @run.update!(state: "running", started_at: Time.current)
      client = @run.client
      docs = client.documents.fiscal.in_period(@run.period_start, @run.period_end).includes(:items)
      canonicals = []
      by_date = Hash.new { |h, k| h[k] = [] }
      docs.each do |d|
        canonical = d.canonical.merge("_id" => d.id)
        canonicals << canonical
        by_date[d.reference_date] << canonical
      end

      intervals = Audit::TemporalPartition.call(client:, period_start: @run.period_start, period_end: @run.period_end)
      skipped_scenario_rules = []
      slices = intervals.map { |interval| build_slice(client, interval) }
      coverage = Audit::Coverage.new
      slices.each do |slice|
        slice[:documents] = by_date.select { |date, _| slice[:interval].cover?(date) }.values.flatten(1)
        slice[:documents].each { |canonical| slice[:engine].evaluate_document(canonical) }
        coverage.add(slice[:documents], slice[:catalog])
        skipped_scenario_rules.concat(slice[:skipped_scenario_rules])
      end

      invalidations = client.documents.where(kind: "invalidation").map { |d| d.data["invalidation"] }
      events = client.documents.where(kind: "event").where(target_access_key: canonicals.map { |c| c["access_key"] }).map { |d| d.data }
      stats = Audit::Stats.new(canonicals)
      fiscal_file_record = client.fiscal_files.where(kind: "sped_icms_ipi", state: "done")
                                 .where("period_start <= ? AND period_end >= ?", @run.period_end, @run.period_start)
                                 .order(created_at: :desc).first
      fiscal_file = fiscal_file_record && Audit::SpedContext.build(fiscal_file_record)
      # Escopos de período apuram o período inteiro: cada regra é avaliada UMA vez, na última fatia em que
      # esteve vigente. Avaliar só a última fatia deixava de fora (em silêncio, sem evaluation_error) a regra
      # cuja vigência termina no meio do período; a resolução do último dia continua valendo para as demais.
      period_ctx = { "documents" => canonicals, "invalidations" => invalidations, "events" => events }
      pending = slices.flat_map { |s| s[:engine].period_rule_ids }.uniq
      slices.reverse_each do |slice|
        ids = slice[:engine].period_rule_ids & pending
        next if ids.empty?
        slice[:engine].evaluate_period(period_ctx, stats:, fiscal_file:, only: ids)
        pending -= ids
      end

      findings = slices.flat_map { |s| s[:engine].findings }
      errors = merge_errors(slices.flat_map { |s| s[:engine].errors })
      if skipped_scenario_rules.any?
        codes = skipped_scenario_rules.uniq
        errors << { rule_code: "SCENARIO", error: "cliente sem cenário tributário publicado — #{codes.size} regra(s) dependente(s) de cenário não avaliadas (publique o cenário e reprocesse)", count: codes.size }
      end
      slices.flat_map { |s| s[:warnings] }.uniq.each { |w| errors << { rule_code: "OVERRIDE", error: w, count: 1 } }

      # Estados lidos ANTES do delete_all: no reprocesso do mesmo run os findings a herdar são os deste run,
      # e apagá-los primeiro faria a justificativa do contador morrer.
      inherited = inherited_states(findings.map { |f| dedupe_key(f) }.uniq)
      ActiveRecord::Base.transaction do
        # retentativa do job (ou reprocesso do mesmo run) não pode colidir com o índice único (audit_run_id, dedupe_key)
        @run.findings.delete_all
        persist(findings, inherited)
        @run.update!(coverage: coverage.result, state: "done", finished_at: Time.current, documents_count: docs.size,
                     findings_count: findings.uniq { |f| dedupe_key(f) }.size, evaluation_errors: errors,
                     snapshot: snapshot(slices, fiscal_file_record))
      end
    rescue => e
      @run.update!(state: "failed", finished_at: Time.current, evaluation_errors: [{ fatal: e.message }])
      raise
    end

    private

    def build_slice(client, interval)
      date = interval.from
      scenario = Scenario::TaxScenario.resolve(client, date)
      catalog = Catalog::Lookup.new(date:, firm_id: client.firm_id, client_id: client.id)
      resolver = Rules::Resolver.new(client:, date:)
      rules = resolver.call
      skipped = []
      if scenario.nil?
        rules, skipped_rules = rules.partition { |r| !scenario_dependent?(r.definition) }
        skipped = skipped_rules.map { |r| r.definition["code"] }
      end
      { interval:, catalog:, scenario:, rules:, warnings: resolver.warnings, skipped_scenario_rules: skipped,
        engine: Rules::Engine.new(rules, catalog:, scenario: scenario&.data || {}) }
    end

    # A regra depende de cenário quando lê `scenario.*` em algum `field`/`ref`/`calc` da definição.
    # Procurar `"scenario.` no JSON classificava errado uma regra cuja mensagem/valor literal citasse o caminho.
    def scenario_dependent?(definition)
      found = false
      walk = ->(node) {
        return if found
        case node
        when Hash
          found ||= [node["field"], node["ref"]].any? { |p| p.is_a?(String) && p.start_with?("scenario.") }
          found ||= calc_reads_scenario?(node["calc"]) if !found && node["calc"].is_a?(String)
          node.each_value { |v| walk.(v) } unless found
        when Array then node.each { |v| walk.(v) }
        end
      }
      walk.(definition)
      found
    end

    def calc_reads_scenario?(expr)
      Rules::Dsl::Calc.tokens(expr).any? { |type, value| type == :id && value.to_s.start_with?("scenario.") }
    rescue Rules::EvaluationError
      false
    end

    def merge_errors(list)
      list.each_with_object([]) do |e, acc|
        existing = acc.find { |x| x[:rule_code] == e[:rule_code] && x[:error] == e[:error] }
        existing ? existing[:count] += e[:count].to_i : acc << e.dup
      end
    end

    def snapshot(slices, fiscal_file_record)
      by_interval = slices.map do |s|
        { "from" => s[:interval].from, "to" => s[:interval].to, "documents" => s[:documents].size,
          "rule_ids" => s[:rules].map { |r| r.rule.id }, "rule_override_ids" => s[:rules].flat_map(&:override_ids).uniq,
          "reference_version_ids" => s[:catalog].versions_used, "reference_row_override_ids" => s[:catalog].row_override_ids_used,
          "scenario_version_id" => s[:scenario]&.id }
      end
      { rule_ids: by_interval.flat_map { |s| s["rule_ids"] }.uniq, rule_override_ids: by_interval.flat_map { |s| s["rule_override_ids"] }.uniq,
        reference_version_ids: by_interval.map { |s| s["reference_version_ids"] }.reduce({}, :merge),
        reference_row_override_ids: by_interval.flat_map { |s| s["reference_row_override_ids"] }.uniq,
        scenario_version_id: by_interval.last["scenario_version_id"], fiscal_file_id: fiscal_file_record&.id,
        by_interval:, dsl_version: 1 }
    end

    def persist(engine_findings, inherited)
      rows = engine_findings.uniq { |f| dedupe_key(f) }.map do |f|
        key = dedupe_key(f)
        { audit_run_id: @run.id, client_id: @run.client_id, rule_id: f.rule.id, rule_code: f.definition["code"], rule_source: f.source,
          document_id: f.document_id, item_number: f.item_number, fiscal_record_id: f.fiscal_record_id, scope: f.definition["scope"], severity: f.definition["severity"],
          shadow: f.rule.shadow?, message: f.message, evidence: f.evidence, group_key: f.group_key, dedupe_key: key,
          state: "open", state_note: nil, created_at: Time.current, updated_at: Time.current }
      end
      rows.each do |r|
        state, note = inherited[r[:dedupe_key]]
        next unless state
        r[:state] = state
        r[:state_note] = note
      end
      Audit::Finding.insert_all!(rows) if rows.any?
    end

    # Último estado NÃO-aberto de cada dedupe_key do cliente; herda só o que veio de decisão humana.
    # Limitado às chaves deste run — sem isso a consulta cresce com o histórico inteiro do cliente.
    def inherited_states(keys)
      return {} if keys.empty?
      keys.each_slice(1_000).each_with_object({}) do |slice, acc|
        Audit::Finding.where(client_id: @run.client_id, dedupe_key: slice).where.not(state: "open")
          .select("DISTINCT ON (dedupe_key) dedupe_key, state, state_note")
          .order(Arel.sql("dedupe_key, created_at DESC, id DESC"))
          .each { |f| acc[f.dedupe_key] = [f.state, f.state_note] if INHERITED_STATES.include?(f.state) }
      end
    end

    # A sombra é regra ADICIONAL (DSL_RULES §11): sem marcar a chave, o disparo dela no mesmo alvo e com a mesma
    # evidência da publicada era descartado pelo uniq e o painel de sombra media taxa de disparo a menos.
    # A chave da regra publicada continua idêntica — a herança de estado posta pelo contador não se perde.
    def dedupe_key(f)
      code = f.rule.shadow? ? "shadow|#{f.definition['code']}" : f.definition["code"]
      [code, f.document_id, f.item_number, f.fiscal_record_id, f.evidence.values.join(",")].join("|")
    end
  end
end
