module Rules
  module Primitives
    class ItemsSumMatchesTotals < Base
      register "items_sum_matches_totals"
      scope "document"
      params_schema fields: { default: %w[products icms_base icms icms_st ipi pis cofins] }, tolerance: { default: "0.01" }
      vars :field, :total, :items_sum, :difference

      def call
        doc = @ctx["doc"]
        totals, sums = doc["totals"] || {}, doc.dig("totals", "items_sum") || {}
        tol = dec(@params["tolerance"])
        Array(@params["fields"]).filter_map do |f|
          next unless totals.key?(f) && sums.key?(f)
          a, b = dec(totals[f]), dec(sums[f])   # total não numérico vira evaluation_error da regra, não exceção do run
          next if (a - b).abs <= tol
          { target: {}, evidence: { "field" => f, "total" => a.to_s("F"), "items_sum" => b.to_s("F") },
            vars: { "field" => f, "total" => a, "items_sum" => b, "difference" => (a - b) } }
        end
      end
    end
  end
end
