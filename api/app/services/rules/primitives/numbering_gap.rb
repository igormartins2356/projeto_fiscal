module Rules
  module Primitives
    # Lacunas de numeração por (modelo, série) do emitente monitorado, descontando inutilizações.
    class NumberingGap < Base
      register "numbering_gap"
      scope "cross_document"
      params_schema max_gap_ignored: { default: 0 }, consider_invalidations: { default: true }

      def call
        docs = (@ctx.dig("period", "documents") || []).select { |d| d["role"] == "issuer" && d.dig("issuance", "number") }
        inval = @params["consider_invalidations"] ? (@ctx.dig("period", "invalidations") || []) : []
        docs.group_by { |d| [d["model"], d.dig("issuance", "series")] }.flat_map do |(model, series), group|
          numbers = group.map { |d| d.dig("issuance", "number") }.uniq.sort
          covered = inval.select { |i| i["model"] == model && i["series"].to_s == series.to_s }
          gaps = []
          numbers.each_cons(2) do |a, b|
            next if b - a <= 1 + @params["max_gap_ignored"].to_i
            missing = ((a + 1)..(b - 1)).reject { |n| covered.any? { |i| n.between?(i["first_number"].to_i, i["last_number"].to_i) } }
            gaps << missing unless missing.empty?
          end
          gaps.map do |missing|
            first = group.min_by { |d| d.dig("issuance", "number") }
            { target: { document_id: first["_id"] },
              evidence: { "model" => model, "series" => series, "missing_from" => missing.first, "missing_to" => missing.last, "missing_count" => missing.size },
              vars: { "model" => model, "series" => series, "missing_from" => missing.first, "missing_to" => missing.last, "missing_count" => missing.size } }
          end
        end
      end
    end
  end
end
