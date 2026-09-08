module Rules
  module Primitives
    # Devoluções emitidas pelo cliente (finNFe=4) confrontadas com a nota original na base.
    # check: "missing" (original do próprio cliente não encontrada), "exceeds" (quantidade devolvida acumulada > original),
    #        "mirror" (item da devolução não espelha CST/CSOSN, alíquota, PIS/COFINS e CFOP correspondente da original), "all".
    class ReturnReferencesOriginal < Base
      register "return_references_original"
      scope "cross_document"
      params_schema check: { default: "all" }, tolerance: { default: "0.0001" },
                    mirror_fields: { default: %w[icms.situation_code icms.rate pis.cst cofins.cst] },
                    cfop_mirror: { default: { "5101" => %w[1201], "6101" => %w[2201], "5102" => %w[1202], "6102" => %w[2202], "5401" => %w[1410], "6401" => %w[2410], "5403" => %w[1411], "6403" => %w[2411], "5405" => %w[1411 1202], "6404" => %w[2411 2202], "5103" => %w[1201], "5104" => %w[1202], "5105" => %w[1201], "5106" => %w[1202], "7101" => %w[3201], "7102" => %w[3202] } }
      vars :referenced_access_key, :original_access_key, :product_code, :returned_quantity, :original_quantity, :problem, :field, :found, :expected, :original_cfop

      def call
        docs = @ctx.dig("period", "documents") || []
        by_key = docs.to_h { |d| [d["access_key"], d] }
        returns = docs.select { |d| d.dig("issuance", "purpose") == "return" && d["role"] == "issuer" }
        hits = []
        returned = Hash.new { |h, k| h[k] = Hash.new(BigDecimal("0")) }

        returns.each do |ret|
          (ret["references"] || []).each do |ref|
            next unless ref["kind"] == "nfe"
            original = by_key[ref["access_key"]]
            issuer_of_ref = ref["access_key"].to_s[6, 14]
            if original.nil?
              next unless check?("missing") && issuer_of_ref == ret["monitored_cnpj"]
              hits << { target: { document_id: ret["_id"] }, evidence: { "referenced_access_key" => ref["access_key"] }, vars: { "referenced_access_key" => ref["access_key"], "problem" => "original_not_found" } }
              next
            end
            ret["items"].each do |it|
              code = it.dig("product", "code")
              returned[original["access_key"]][code] += BigDecimal((it.dig("product", "commercial_quantity") || "0").to_s)
              hits.concat(mirror(ret, it, original)) if check?("mirror")
            end
          end
        end

        if check?("exceeds")
          returned.each do |okey, per_product|
            original = by_key[okey]
            per_product.each do |code, qty|
              orig_qty = original["items"].select { |i| i.dig("product", "code") == code }.sum(BigDecimal("0")) { |i| BigDecimal((i.dig("product", "commercial_quantity") || "0").to_s) }
              next if orig_qty.zero? || qty <= orig_qty + BigDecimal(@params["tolerance"].to_s)
              ret = returns.find { |r| (r["references"] || []).any? { |x| x["access_key"] == okey } && r["items"].any? { |i| i.dig("product", "code") == code } }
              hits << { target: { document_id: ret&.dig("_id") }, evidence: { "original_access_key" => okey, "product_code" => code, "returned_quantity" => qty.to_s("F"), "original_quantity" => orig_qty.to_s("F") },
                        vars: { "original_access_key" => okey, "product_code" => code, "returned_quantity" => qty, "original_quantity" => orig_qty, "problem" => "exceeds_original" } }
            end
          end
        end
        hits
      end

      private

      def check?(name) = @params["check"] == "all" || Array(@params["check"]).include?(name)

      # Espelho: mesmo produto na original (por código); compara campos tributários e o CFOP de devolução correspondente
      def mirror(ret, it, original)
        code = it.dig("product", "code")
        orig_item = original["items"].find { |i| i.dig("product", "code") == code } or return []
        out = []
        Array(@params["mirror_fields"]).each do |field|
          a, b = Dsl::Path.fetch(it, field), Dsl::Path.fetch(orig_item, field)
          next if Dsl::Path.absent?(b) || b.nil?
          next if !Dsl::Path.absent?(a) && !a.nil? && Dsl::Value.equal?(a, b)
          out << { target: { document_id: ret["_id"], item_number: it["number"] }, evidence: { "product_code" => code, "field" => field, "found" => (Dsl::Path.absent?(a) ? nil : a.to_s), "expected" => b.to_s, "original_access_key" => original["access_key"] },
                   vars: { "product_code" => code, "field" => field, "found" => (Dsl::Path.absent?(a) ? "—" : a), "expected" => b, "original_access_key" => original["access_key"], "problem" => "mirror" } }
        end
        expected_cfops = @params["cfop_mirror"][orig_item.dig("product", "cfop").to_s]
        if expected_cfops && !expected_cfops.include?(it.dig("product", "cfop").to_s)
          out << { target: { document_id: ret["_id"], item_number: it["number"] }, evidence: { "product_code" => code, "field" => "product.cfop", "found" => it.dig("product", "cfop"), "expected" => expected_cfops.join("/"), "original_cfop" => orig_item.dig("product", "cfop"), "original_access_key" => original["access_key"] },
                   vars: { "product_code" => code, "field" => "product.cfop", "found" => it.dig("product", "cfop"), "expected" => expected_cfops.join("/"), "original_cfop" => orig_item.dig("product", "cfop"), "original_access_key" => original["access_key"], "problem" => "mirror" } }
        end
        out
      end
    end
  end
end
