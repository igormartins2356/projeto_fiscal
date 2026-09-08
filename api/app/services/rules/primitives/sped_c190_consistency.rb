module Rules
  module Primitives
    # Registro analítico C190 deve consolidar os C170 do mesmo C100 por (CST, CFOP, alíquota).
    class SpedC190Consistency < Base
      register "sped_c190_consistency"
      scope "period"
      params_schema tolerance: { default: "0.05" }
      vars :access_key, :cst, :cfop, :aliq, :field, :file_value, :expected_value, :line, :problem

      SUMS = { "VL_BC_ICMS" => "VL_BC_ICMS", "VL_ICMS" => "VL_ICMS", "VL_ICMS_ST" => "VL_ICMS_ST", "VL_IPI" => "VL_IPI" }.freeze

      def call
        file = @ctx["fiscal_file"] or return []
        tol = BigDecimal(@params["tolerance"].to_s)
        hits = []
        (file["c100"] || []).each do |r|
          c170, c190 = r["c170"] || [], r["c190"] || []
          next if c170.empty? || c190.empty?
          grouped = c170.group_by { |k| [k.dig("fields", "CST_ICMS").to_s, k.dig("fields", "CFOP").to_s, dec(k.dig("fields", "ALIQ_ICMS")).to_s("F")] }
          c190.each do |a|
            key = [a.dig("fields", "CST_ICMS").to_s, a.dig("fields", "CFOP").to_s, dec(a.dig("fields", "ALIQ_ICMS")).to_s("F")]
            group = grouped[key]
            if group.nil?
              hits << { target: { fiscal_record_id: a["record_id"] }, evidence: { "access_key" => r["access_key"], "cst" => key[0], "cfop" => key[1], "aliq" => key[2], "line" => a["line"] },
                        vars: { "access_key" => r["access_key"], "cst" => key[0], "cfop" => key[1], "aliq" => key[2], "line" => a["line"], "problem" => "no_matching_items" } }
              next
            end
            SUMS.each do |sum_field, item_field|
              fv = dec(a.dig("fields", sum_field))
              expected = group.sum(BigDecimal("0")) { |k| dec(k.dig("fields", item_field)) }
              next if (fv - expected).abs <= tol
              hits << { target: { fiscal_record_id: a["record_id"] }, evidence: { "access_key" => r["access_key"], "cst" => key[0], "cfop" => key[1], "field" => sum_field, "file_value" => fv.to_s("F"), "expected_value" => expected.to_s("F"), "line" => a["line"] },
                        vars: { "access_key" => r["access_key"], "cst" => key[0], "cfop" => key[1], "aliq" => key[2], "field" => sum_field, "file_value" => fv, "expected_value" => expected, "line" => a["line"], "problem" => "sum_mismatch" } }
            end
          end
        end
        hits
      end

      private

      def dec(v) = BigDecimal(v.presence || "0")
    end
  end
end
