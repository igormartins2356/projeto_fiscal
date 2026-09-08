module Rules
  module Primitives
    # Conciliação item a item: C170 × item do XML (NUM_ITEM). CST_ICMS da EFD tem 3 dígitos (origem + CST).
    class SpedItemReconciliation < Base
      register "sped_item_reconciliation"
      scope "period"
      params_schema tolerance: { default: "0.02" },
                    compare_fields: { default: { "CFOP" => "product.cfop", "ALIQ_ICMS" => "icms.rate", "VL_BC_ICMS" => "icms.base_amount", "VL_ICMS" => "icms.amount" } }
      vars :access_key, :number, :item, :field, :file_value, :xml_value, :line, :problem

      def call
        file = @ctx["fiscal_file"] or return []
        docs = (@ctx.dig("period", "documents") || []).to_h { |d| [d["access_key"], d] }
        tol = BigDecimal(@params["tolerance"].to_s)
        hits = []
        (file["c100"] || []).each do |r|
          doc = docs[r["access_key"]] or next
          next unless doc.dig("status", "state") == "authorized"
          items = (doc["items"] || []).to_h { |i| [i["number"], i] }
          c170 = r["c170"] || []
          if c170.any? && c170.size != items.size
            hits << { target: { document_id: doc["_id"], fiscal_record_id: r["record_id"] },
                      evidence: { "access_key" => r["access_key"], "file_items" => c170.size, "xml_items" => items.size },
                      vars: { "access_key" => r["access_key"], "number" => doc.dig("issuance", "number"), "file_value" => c170.size, "xml_value" => items.size, "field" => "quantidade de itens", "problem" => "item_count" } }
          end
          c170.each do |k|
            item = items[k.dig("fields", "NUM_ITEM").to_i] or next
            @params["compare_fields"].each do |file_field, item_path|
              fv, iv = k.dig("fields", file_field), Dsl::Path.fetch(item, item_path)
              next if fv.blank? || Dsl::Path.absent?(iv) || iv.nil?
              equal = if fv.match?(/\A-?\d+(\.\d+)?\z/) && iv.to_s.match?(/\A-?\d+(\.\d+)?\z/)
                        (BigDecimal(fv) - BigDecimal(iv.to_s)).abs <= tol
                      else
                        fv.to_s == iv.to_s
                      end
              next if equal
              hits << { target: { document_id: doc["_id"], item_number: item["number"], fiscal_record_id: k["record_id"] },
                        evidence: { "access_key" => r["access_key"], "item" => item["number"], "field" => file_field, "file_value" => fv, "xml_value" => iv.to_s, "line" => k["line"] },
                        vars: { "access_key" => r["access_key"], "number" => doc.dig("issuance", "number"), "item" => item["number"], "field" => file_field, "file_value" => fv, "xml_value" => iv, "line" => k["line"], "problem" => "item_mismatch" } }
            end
            # CST com origem (3 dígitos) — compara origem e CST separadamente quando o item usa CST
            file_cst = k.dig("fields", "CST_ICMS").to_s
            if file_cst.match?(/\A\d{3}\z/) && item.dig("icms", "cst").present?
              if file_cst[1, 2] != item.dig("icms", "cst")
                hits << { target: { document_id: doc["_id"], item_number: item["number"], fiscal_record_id: k["record_id"] },
                          evidence: { "access_key" => r["access_key"], "item" => item["number"], "field" => "CST_ICMS", "file_value" => file_cst, "xml_value" => "#{item.dig('icms', 'origin')}#{item.dig('icms', 'cst')}", "line" => k["line"] },
                          vars: { "access_key" => r["access_key"], "number" => doc.dig("issuance", "number"), "item" => item["number"], "field" => "CST_ICMS", "file_value" => file_cst, "xml_value" => "#{item.dig('icms', 'origin')}#{item.dig('icms', 'cst')}", "line" => k["line"], "problem" => "item_mismatch" } }
              end
            end
          end
        end
        hits
      end
    end
  end
end
