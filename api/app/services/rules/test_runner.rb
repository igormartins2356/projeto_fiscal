module Rules
  # Executa os casos de teste de uma versão de regra (DSL_RULES.md §10) e grava o resultado.
  class TestRunner
    Result = Struct.new(:test_case, :passed, :findings, :errors, :details, keyword_init: true)

    def initialize(rule) = @rule = rule

    def run_all = @rule.test_cases.map { |tc| run(tc) }

    def run(tc)
      catalog = StubCatalog.new(tc.catalog, date: tc.reference_date)
      doc = build_document(tc, catalog)
      resolved = Rules::Resolver::ResolvedRule.new(rule: @rule, definition: @rule.definition, source: "platform", override_ids: [])
      engine = Rules::Engine.new([resolved], catalog:, scenario: default_scenario.merge(tc.scenario || {}))
      if %w[item document].include?(@rule.scope)
        engine.evaluate_document(doc)
      else
        engine.evaluate_period({ "documents" => [doc], "invalidations" => [], "events" => [] })
      end
      passed, details = compare(tc.expect, engine)
      tc.update!(last_result: passed ? "passed" : "failed", last_run_at: Time.current)
      Result.new(test_case: tc, passed:, findings: engine.findings.map { |f| finding_json(f) }, errors: engine.errors, details:)
    end

    private

    def build_document(tc, catalog)
      input = tc.input || {}
      canonical = if input["kind"] == "xml"
        xml = input["xml"].presence || File.read(Rails.root.join(input["fixture"]))
        Ingestion::Nfe::Parser.call(xml)
      else
        (input["document"] || {}).deep_dup
      end
      cnpj = input["monitored_cnpj"] || canonical.dig("issuer", "cnpj") || "00000000000000"
      Ingestion::Nfe::Derivations.call(canonical, monitored_cnpj: cnpj, catalog:) if %w[nfe nfce].include?(canonical["kind"]) && input["derive"] != false
      canonical["items"] ||= []
      canonical.merge("_id" => 0)
    end

    def compare(expect, engine)
      expected = Array(expect["findings"])
      actual = engine.findings
      return [false, ["erros de avaliação: #{engine.errors.map { |e| e[:error] }.join('; ')}"]] if engine.errors.any?
      return [actual.empty?, actual.empty? ? [] : ["esperava nenhum finding, obteve #{actual.size}"]] if expected.empty?
      missing = expected.reject { |e| actual.any? { |a| matches?(e, a) } }
      details = missing.map { |m| "finding esperado não encontrado: #{m.to_json}" }
      details << "esperava #{expected.size} finding(s), obteve #{actual.size}" if expected.size != actual.size
      [details.empty?, details]
    end

    def matches?(e, a)
      (e["item_number"].nil? || e["item_number"] == a.item_number) &&
        (e["severity"].nil? || e["severity"] == a.definition["severity"]) &&
        (e["evidence"].nil? || e["evidence"].all? { |k, v| a.evidence[k].to_s == v.to_s }) &&
        (e["message_includes"].nil? || a.message.include?(e["message_includes"]))
    end

    def finding_json(f) = { item_number: f.item_number, severity: f.definition["severity"], message: f.message, evidence: f.evidence }

    def default_scenario = { "tax_regime" => "simples_nacional", "uf" => "SP", "icms_taxpayer" => true, "ipi_taxpayer" => false, "activity" => ["commerce"], "pis_cofins" => { "regime" => "simples" } }

    # Catálogo real + sobreposição do caso de teste (tabela → linhas)
    class StubCatalog
      def initialize(stub, date:)
        @stub = (stub || {}).transform_values { |rows| rows.to_h { |r| [Array(r["key"]).map(&:to_s), r["data"]] } }
        @real = Catalog::Lookup.new(date:, overrides_enabled: false)
      end
      def lookup(table, key, strict: false) = @stub.key?(table) ? @stub[table][Array(key).map(&:to_s)] : @real.lookup(table, key, strict:)
      def versions_used = @real.versions_used
    end
  end
end
