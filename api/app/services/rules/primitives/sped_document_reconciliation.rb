module Rules
  module Primitives
    # Conciliação NF-e (modelo 55, emissão própria) × registros C100 da EFD.
    # check: "presence" (XML autorizada fora do arquivo / C100 sem XML), "cancelled" (cancelada com COD_SIT errado ou ausente),
    #        "values" (totais divergentes, campo a campo).
    class SpedDocumentReconciliation < Base
      register "sped_document_reconciliation"
      scope "period"
      # COD_SIT/modelos/IND_EMIT são tabela do Guia Prático (têm vigência): vêm da regra, não do código.
      params_schema check: { default: "presence" }, tolerance: { default: "0.01" },
                    models: { default: nil }, own_issue_ind_emit: { default: nil },
                    cancelled_cod_sit: { default: nil }, analytic_cod_sit: { default: nil }, values_cod_sit: { default: nil },
                    compare_fields: { default: { "VL_DOC" => "totals.total", "VL_BC_ICMS" => "totals.icms_base", "VL_ICMS" => "totals.icms",
                                                 "VL_BC_ICMS_ST" => "totals.icms_st_base", "VL_ICMS_ST" => "totals.icms_st", "VL_IPI" => "totals.ipi",
                                                 "VL_PIS" => "totals.pis", "VL_COFINS" => "totals.cofins" } }
      vars :access_key, :number, :series, :cod_sit, :field, :file_value, :xml_value, :line, :problem

      def call
        file = @ctx["fiscal_file"] or return []
        models = Array(param!("models")).map(&:to_s)
        all_docs = @ctx.dig("period", "documents") || []
        docs = all_docs.select { |d| d["model"].in?(models) && d["role"] == "issuer" && d.dig("operation", "direction") == "outbound" }
        by_key = docs.to_h { |d| [d["access_key"], d] }
        # a busca "esse C100 tem XML?" olha TODAS as notas do período: emissão própria de entrada
        # (devolução, retorno de industrialização) está na base como inbound e não entra em `docs`
        keys_in_base = all_docs.filter_map { |d| d["access_key"].presence }.to_set
        c100 = file["c100"] || []
        c100_by_key = c100.select { |r| r["access_key"].present? }.group_by { |r| r["access_key"] }
        c100_by_num = c100.group_by { |r| [r.dig("fields", "COD_MOD"), r.dig("fields", "SER").to_s, r.dig("fields", "NUM_DOC").to_s.to_i] }
        find_recs = ->(d) { c100_by_key[d["access_key"]] || c100_by_num[[d["model"], d.dig("issuance", "series").to_s, d.dig("issuance", "number").to_i]] }
        hits = []

        case @params["check"]
        when "presence"
          docs.select { |d| d.dig("status", "state") == "authorized" }.each do |d|
            next if find_recs.(d)
            hits << { target: { document_id: d["_id"] }, evidence: { "access_key" => d["access_key"], "number" => d.dig("issuance", "number"), "series" => d.dig("issuance", "series") },
                      vars: { "access_key" => d["access_key"], "number" => d.dig("issuance", "number"), "series" => d.dig("issuance", "series"), "problem" => "missing_in_file" } }
          end
          own_issue = param!("own_issue_ind_emit").to_s
          c100.each do |r|
            next if r["access_key"].blank? || keys_in_base.include?(r["access_key"]) || r.dig("fields", "IND_EMIT").to_s != own_issue
            hits << { target: { fiscal_record_id: r["record_id"] }, evidence: { "access_key" => r["access_key"], "line" => r["line"], "number" => r.dig("fields", "NUM_DOC") },
                      vars: { "access_key" => r["access_key"], "line" => r["line"], "number" => r.dig("fields", "NUM_DOC"), "problem" => "not_in_xml" } }
          end
        when "cancelled"
          cancelled_sit = Array(param!("cancelled_cod_sit")).map(&:to_s)
          docs.select { |d| d.dig("status", "state") == "cancelled" }.each do |d|
            recs = find_recs.(d)
            if recs.nil?
              hits << { target: { document_id: d["_id"] }, evidence: { "access_key" => d["access_key"], "number" => d.dig("issuance", "number") },
                        vars: { "access_key" => d["access_key"], "number" => d.dig("issuance", "number"), "cod_sit" => "ausente", "problem" => "cancelled_missing" } }
            else
              recs.reject { |r| cancelled_sit.include?(r.dig("fields", "COD_SIT").to_s) }.each do |r|
                hits << { target: { document_id: d["_id"], fiscal_record_id: r["record_id"] }, evidence: { "access_key" => d["access_key"], "cod_sit" => r.dig("fields", "COD_SIT"), "line" => r["line"] },
                          vars: { "access_key" => d["access_key"], "cod_sit" => r.dig("fields", "COD_SIT"), "line" => r["line"], "problem" => "cancelled_wrong_sit" } }
              end
            end
          end
        when "analytic"
          # Guia: para cada C100 regular deve haver pelo menos um C190 (C170 é dispensado na NF-e de emissão própria — Exceção 2)
          own_issue = param!("own_issue_ind_emit").to_s
          analytic_sit = Array(param!("analytic_cod_sit")).map(&:to_s)
          c100.each do |r|
            next unless r.dig("fields", "IND_EMIT").to_s == own_issue && r.dig("fields", "COD_SIT").to_s.in?(analytic_sit)
            next if (r["c190"] || []).any?
            hits << { target: { fiscal_record_id: r["record_id"], document_id: by_key.dig(r["access_key"], "_id") },
                      evidence: { "access_key" => r["access_key"], "number" => r.dig("fields", "NUM_DOC"), "line" => r["line"] },
                      vars: { "access_key" => r["access_key"], "number" => r.dig("fields", "NUM_DOC"), "line" => r["line"], "problem" => "missing_c190" } }
          end
        when "values"
          tol = dec(@params["tolerance"])
          values_sit = Array(param!("values_cod_sit")).map(&:to_s)
          c100.each do |r|
            doc = by_key[r["access_key"]] or next
            next unless doc.dig("status", "state") == "authorized" && r.dig("fields", "COD_SIT").to_s.in?(values_sit)
            @params["compare_fields"].each do |file_field, doc_path|
              fv, dv = r.dig("fields", file_field), Dsl::Path.fetch(doc, doc_path)
              next if fv.blank? || Dsl::Path.absent?(dv) || dv.nil?
              a, b = dec(fv), dec(dv)
              next if (a - b).abs <= tol
              hits << { target: { document_id: doc["_id"], fiscal_record_id: r["record_id"] },
                        evidence: { "access_key" => r["access_key"], "field" => file_field, "file_value" => a.to_s("F"), "xml_value" => b.to_s("F"), "line" => r["line"] },
                        vars: { "access_key" => r["access_key"], "number" => doc.dig("issuance", "number"), "field" => file_field, "file_value" => a, "xml_value" => b, "line" => r["line"], "problem" => "value_mismatch" } }
            end
          end
        end
        hits
      end
    end
  end
end
