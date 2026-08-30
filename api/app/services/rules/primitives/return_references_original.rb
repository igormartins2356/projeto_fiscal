module Rules
  module Primitives
    # Devoluções: referência deve existir (quando a original é do próprio cliente) e quantidades devolvidas (acumuladas) não podem exceder a original.
    class ReturnReferencesOriginal < Base
      register "return_references_original"
      scope "cross_document"
      params_schema require_resolved: { default: true }, compare: { default: "quantity" }, tolerance: { default: "0.0001" }

      def call
        docs = @ctx.dig("period", "documents") || []
        by_key = docs.to_h { |d| [d["access_key"], d] }
        returns = docs.select { |d| d.dig("issuance", "purpose") == "return" && d["role"] == "issuer" }
        hits = []
        returned_by_original = Hash.new { |h, k| h[k] = Hash.new(BigDecimal("0")) }

        returns.each do |ret|
          (ret["references"] || []).each do |ref|
            next unless ref["kind"] == "nfe"
            original = by_key[ref["access_key"]]
            issuer_of_ref = ref["access_key"].to_s[6, 14]
            if original.nil?
              next unless @params["require_resolved"] && issuer_of_ref == ret["monitored_cnpj"]
              hits << { target: { document_id: ret["_id"] }, evidence: { "referenced_access_key" => ref["access_key"] },
                        vars: { "referenced_access_key" => ref["access_key"], "problem" => "original_not_found" } }
              next
            end
            ret["items"].each do |it|
              code = it.dig("product", "code")
              returned_by_original[original["access_key"]][code] += BigDecimal((it.dig("product", "commercial_quantity") || "0").to_s)
            end
          end
        end

        returned_by_original.each do |okey, per_product|
          original = by_key[okey]
          per_product.each do |code, qty|
            orig_qty = original["items"].select { |i| i.dig("product", "code") == code }.sum(BigDecimal("0")) { |i| BigDecimal((i.dig("product", "commercial_quantity") || "0").to_s) }
            next if orig_qty.zero? || qty <= orig_qty + BigDecimal(@params["tolerance"].to_s)
            ret = returns.find { |r| (r["references"] || []).any? { |x| x["access_key"] == okey } && r["items"].any? { |i| i.dig("product", "code") == code } }
            hits << { target: { document_id: ret&.dig("_id") }, evidence: { "original_access_key" => okey, "product_code" => code, "returned_quantity" => qty.to_s("F"), "original_quantity" => orig_qty.to_s("F") },
                      vars: { "original_access_key" => okey, "product_code" => code, "returned_quantity" => qty, "original_quantity" => orig_qty, "problem" => "exceeds_original" } }
          end
        end
        hits
      end
    end
  end
end
