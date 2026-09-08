module Audit
  # Orquestra um AuditRun: resolve cenário, regras e catálogo; roda o motor; persiste findings com estado herdado.
  class Runner
    def initialize(run) = @run = run

    def call
      @run.update!(state: "running", started_at: Time.current)
      client = @run.client
      date = @run.period_end
      scenario = Scenario::TaxScenario.resolve(client, date)
      catalog = Catalog::Lookup.new(date:, firm_id: client.firm_id, client_id: client.id)
      rules = Rules::Resolver.new(client:, date:).call
      skipped_scenario_rules = []
      if scenario.nil?
        rules, skipped_scenario_rules = rules.partition { |r| !r.definition.to_json.match?(/"scenario\./) }
      end
      engine = Rules::Engine.new(rules, catalog:, scenario: scenario&.data || {})

      docs = client.documents.fiscal.in_period(@run.period_start, @run.period_end).includes(:items)
      canonicals = docs.map { |d| d.canonical.merge("_id" => d.id) }
      canonicals.each { |c| engine.evaluate_document(c) }
      invalidations = client.documents.where(kind: "invalidation").map { |d| d.data["invalidation"] }
      events = client.documents.where(kind: "event").where(target_access_key: canonicals.map { |c| c["access_key"] }).map { |d| d.data }
      stats = Audit::Stats.new(canonicals)
      fiscal_file_record = client.fiscal_files.where(kind: "sped_icms_ipi", state: "done")
                                 .where("period_start <= ? AND period_end >= ?", @run.period_end, @run.period_start)
                                 .order(created_at: :desc).first
      fiscal_file = fiscal_file_record && Audit::SpedContext.build(fiscal_file_record)
      engine.evaluate_period({ "documents" => canonicals, "invalidations" => invalidations, "events" => events }, stats:, fiscal_file:)

      if skipped_scenario_rules.any?
        engine.errors << { rule_code: "SCENARIO", error: "cliente sem cenário tributário publicado — #{skipped_scenario_rules.size} regra(s) dependente(s) de cenário não avaliadas (publique o cenário e reprocesse)", count: skipped_scenario_rules.size }
      end
      persist(engine)
      coverage = Audit::Coverage.report(canonicals, catalog)
      @run.update!(coverage:, state: "done", finished_at: Time.current, documents_count: docs.size, findings_count: engine.findings.size,
                   evaluation_errors: engine.errors,
                   snapshot: { rule_ids: rules.map { |r| r.rule.id }, rule_override_ids: rules.flat_map(&:override_ids),
                               reference_version_ids: catalog.versions_used, scenario_version_id: scenario&.id, fiscal_file_id: fiscal_file_record&.id, dsl_version: 1 })
    rescue => e
      @run.update!(state: "failed", finished_at: Time.current, evaluation_errors: [{ fatal: e.message }])
      raise
    end

    private

    def persist(engine)
      previous = Audit::Finding.where(client_id: @run.client_id).where.not(state: "open")
                   .order(created_at: :desc).pluck(:dedupe_key, :state, :state_note).uniq(&:first).to_h { |k, s, n| [k, [s, n]] }
      rows = engine.findings.uniq { |f| dedupe_key(f) }.map do |f|
        key = dedupe_key(f)
        state, note = previous[key]
        { audit_run_id: @run.id, client_id: @run.client_id, rule_id: f.rule.id, rule_code: f.definition["code"], rule_source: f.source,
          document_id: f.document_id, item_number: f.item_number, fiscal_record_id: f.fiscal_record_id, scope: f.definition["scope"], severity: f.definition["severity"],
          shadow: f.rule.shadow?, message: f.message, evidence: f.evidence, group_key: f.group_key, dedupe_key: key,
          state: state || "open", state_note: note, created_at: Time.current, updated_at: Time.current }
      end
      Audit::Finding.insert_all!(rows) if rows.any?
    end

    def dedupe_key(f) = [f.definition["code"], f.document_id, f.item_number, f.fiscal_record_id, f.evidence.values.join(",")].join("|")
  end
end
