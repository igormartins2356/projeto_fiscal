module Rules
  module Primitives
    # Desconfia do cenário: se scenario.<field> == when_field_is mas a fração de itens que satisfazem `evidence` passa do threshold.
    class ScenarioFieldDisagreement < Base
      register "scenario_field_disagreement"
      scope "scenario"
      params_schema field: { default: nil }, evidence: { default: nil }, threshold: { default: "0.2" }, when_field_is: { default: false }
      vars :share_pct, :matching_items, :total_items

      def call
        docs = @ctx.dig("period", "documents") || []
        items = docs.select { |d| d["role"] == "issuer" }.flat_map { |d| (d["items"] || []).map { |i| { "item" => i, "doc" => d } } }
        return [] if items.empty?
        actual = Dsl::Path.fetch(@ctx, "scenario.#{@params['field']}")
        actual = nil if Dsl::Path.absent?(actual)
        return [] unless actual == @params["when_field_is"]
        matches = items.count do |c|
          Dsl::Condition.evaluate(@params["evidence"], @ctx.merge(c))
        rescue EvaluationError
          false
        end
        share = matches.fdiv(items.size)
        return [] if share <= BigDecimal(@params["threshold"].to_s)
        pct = (share * 100).round
        [{ target: {}, evidence: { "scenario_field" => @params["field"], "scenario_value" => actual.to_s, "share_pct" => pct, "matching_items" => matches, "total_items" => items.size },
           vars: { "share_pct" => pct, "matching_items" => matches, "total_items" => items.size } }]
      end
    end
  end
end
