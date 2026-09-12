module Rules
  module Primitives
    # Número maior emitido em data anterior ao número menor (numeração fora de ordem cronológica) por (modelo, série).
    class NumberingOrder < Base
      register "numbering_order"
      scope "cross_document"
      params_schema tolerance_days: { default: 0 }
      vars :model, :series, :number, :issued_at, :previous_number, :previous_issued_at

      def call
        docs = (@ctx.dig("period", "documents") || []).select { |d| d["role"] == "issuer" && d.dig("issuance", "number") && d.dig("issuance", "issued_at") }
        tol = @params["tolerance_days"].to_i
        docs.group_by { |d| [d["model"], d.dig("issuance", "series")] }.flat_map do |(model, series), group|
          sorted = group.sort_by { |d| d.dig("issuance", "number") }
          sorted.each_cons(2).filter_map do |a, b|
            ta, tb = Dsl::Value.to_time(a.dig("issuance", "issued_at")), Dsl::Value.to_time(b.dig("issuance", "issued_at"))
            next unless tb < ta - tol.days
            { target: { document_id: b["_id"] },
              evidence: { "model" => model, "series" => series, "number" => b.dig("issuance", "number"), "issued_at" => b.dig("issuance", "issued_at"), "previous_number" => a.dig("issuance", "number"), "previous_issued_at" => a.dig("issuance", "issued_at") },
              vars: { "model" => model, "series" => series, "number" => b.dig("issuance", "number"), "issued_at" => tb.strftime("%d/%m/%Y"), "previous_number" => a.dig("issuance", "number"), "previous_issued_at" => ta.strftime("%d/%m/%Y") } }
          end
        end
      end
    end
  end
end
