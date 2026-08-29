module Rules
  # Motor genérico: recebe regras resolvidas + contexto → findings (Hash) e evaluation_errors.
  # Não conhece valor fiscal algum.
  class Engine
    Finding = Struct.new(:rule, :definition, :source, :document_id, :item_number, :message, :evidence, :vars, :group_key, keyword_init: true)

    attr_reader :findings, :errors

    def initialize(resolved_rules, catalog:, scenario:)
      @rules = resolved_rules
      @catalog = catalog
      @scenario = scenario
      @findings = []
      @errors = []
    end

    # doc: canônico com "items" e "_id"
    def evaluate_document(doc)
      return if %w[cancelled denied rejected].include?(doc.dig("status", "state"))
      base = { "doc" => doc, "scenario" => @scenario, "catalog" => @catalog }
      @rules.each do |r|
        case r.definition["scope"]
        when "document" then evaluate(r, base, document_id: doc["_id"])
        when "item"
          (doc["items"] || []).each { |item| evaluate(r, base.merge("item" => item), document_id: doc["_id"], item_number: item["number"]) }
        end
      end
    end

    # period: { "documents" => [canônicos], "invalidations" => [], "events" => [] }
    def evaluate_period(period, fiscal_file: nil, stats: nil)
      base = { "period" => period, "scenario" => @scenario, "catalog" => @catalog, "fiscal_file" => fiscal_file, "stats" => stats }
      @rules.select { |r| %w[cross_document period scenario].include?(r.definition["scope"]) }.each { |r| evaluate(r, base) }
    end

    private

    def evaluate(r, ctx, document_id: nil, item_number: nil)
      d = r.definition
      ctx = ctx.merge("params" => d.fetch("params", {}))
      ctx = Dsl::Let.apply(d["let"], ctx)
      return unless Dsl::Condition.evaluate(d["applies_when"], ctx)

      if d["primitive"]
        prim = Primitives::Base.find(d.dig("primitive", "name")).new(d.dig("primitive", "params"), ctx)
        prim.call.each do |hit|
          vctx = ctx.merge(hit[:vars] || {})
          emit(r, vctx, document_id: hit.dig(:target, :document_id) || document_id,
                        item_number: hit.dig(:target, :item_number) || item_number, extra_evidence: hit[:evidence] || {})
        end
      else
        return if Dsl::Condition.evaluate(d["assert"], ctx)
        emit(r, ctx, document_id:, item_number:)
      end
    rescue EvaluationError => e
      @errors << { rule_code: d["code"], version: d["version"], document_id:, item_number:, error: e.message }
    end

    def emit(r, ctx, document_id:, item_number:, extra_evidence: {})
      d = r.definition
      paths = referenced_paths(d)
      evidence = paths.each_with_object({}) do |p, h|
        v = Dsl::Path.fetch(ctx, p)
        h[p] = Dsl::Path.absent?(v) ? nil : Dsl::Template.format(v)
      end.merge(extra_evidence)
      group_key = Array(d["group_by"]).map { |p| Dsl::Template.format(Dsl::Path.fetch(ctx, p)) }.join("|").presence
      @findings << Finding.new(rule: r.rule, definition: d, source: r.source, document_id:, item_number:,
                               message: Dsl::Template.render(d["message"], ctx), evidence:, group_key:)
    end

    def referenced_paths(d)
      fields = []
      walk = ->(node) {
        case node
        when Hash
          fields << node["field"] if node["field"]
          fields << node["ref"] if node["ref"]
          node.each_value { |v| walk.(v) }
        when Array then node.each { |v| walk.(v) }
        end
      }
      walk.(d["applies_when"]); walk.(d["assert"])
      (fields + Dsl::Template.paths(d["message"])).uniq.reject { |f| f.start_with?("params.") }
    end
  end
end
