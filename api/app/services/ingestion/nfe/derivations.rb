module Ingestion
  module Nfe
    # Campos derivados [D] do CANONICO.md §8. Re-executável. Usa Catalog::Lookup na reference_date.
    class Derivations
      REGIME = { "1" => "simples_nacional", "2" => "simples_nacional_excess", "3" => "normal", "4" => "mei" }
      CFOP_GROUP = { "1" => "inbound_intrastate", "2" => "inbound_interstate", "3" => "inbound_foreign", "5" => "outbound_intrastate", "6" => "outbound_interstate", "7" => "outbound_foreign" }

      def self.call(doc, monitored_cnpj:, catalog: nil) = new(doc, monitored_cnpj, catalog).call

      def initialize(doc, monitored_cnpj, catalog)
        @doc = doc
        @cnpj = monitored_cnpj
        @catalog = catalog
      end

      def call
        d = @doc
        return d unless %w[nfe nfce].include?(d["kind"])
        d["monitored_cnpj"] = @cnpj
        d["role"] = d.dig("issuer", "cnpj") == @cnpj ? "issuer" : d.dig("recipient", "cnpj") == @cnpj ? "recipient" : "third_party"
        issued = d.dig("issuance", "issued_at")
        d["reference_date"] = issued && Time.zone.parse(issued).to_date.iso8601
        d["period"] = d["reference_date"]&.slice(0, 7)
        @catalog ||= Catalog::Lookup.new(date: Date.parse(d["reference_date"] || Date.current.iso8601))

        d["issuer"]["tax_regime"] = REGIME.fetch(d.dig("issuer", "crt"), "unknown") if d["issuer"]
        if d["recipient"]
          r = d["recipient"]
          r["person_type"] = r["cnpj"] ? "legal_entity" : r["cpf"] ? "individual" : r["foreign_id"] ? "foreign" : "unidentified"
          r["icms_taxpayer"] = r["ie_indicator"] == "taxpayer"
          r["uf"] = "EX" if r["foreign_id"] && !r["uf"]
        end
        d["operation"]["origin_uf"] = d.dig("issuer", "uf")
        d["operation"]["destination_uf"] = d.dig("recipient", "uf") || (d.dig("operation", "scope") == "foreign" ? "EX" : nil)
        d["operation"]["direction"] = if d["role"] == "recipient" && d.dig("operation", "direction_declared") == "outbound" then "inbound"
                                      elsif d["role"] == "recipient" then "outbound"
                                      else d.dig("operation", "direction_declared")
                                      end
        d["items"].each { |it| derive_item(it, d) }
        cfops = d["items"].map { |i| i.dig("product", "cfop") }.compact.uniq
        d["operation"]["cfops"] = cfops
        d["operation"]["mixed_cfop"] = cfops.size > 1
        d["operation"]["nature"] = nature(d)
        totals(d)
        d["status"] = { "state" => status_state(d.dig("protocol", "status_code")) }
        d["references"].each { |ref| ref["resolved"] = false }
        d
      end

      private

      def derive_item(it, d)
        p = it["product"]
        dec = ->(v) { BigDecimal((v || "0").to_s) }
        net = dec.(p["gross_amount"]) - dec.(p["discount"]) + dec.(p["freight"]) + dec.(p["insurance"]) + dec.(p["other_expenses"])
        it["net_amount"] = fmt(net)
        cfop = p["cfop"].to_s
        it["cfop_group"] = CFOP_GROUP[cfop[0]]
        it["cfop_scope"] = { "1" => "intrastate", "5" => "intrastate", "2" => "interstate", "6" => "interstate", "3" => "foreign", "7" => "foreign" }[cfop[0]]
        cfop_row = @catalog.lookup("cfop", [cfop])
        it["cfop_nature"] = cfop_row&.dig("nature") || "unknown"
        it["cfop_known"] = !cfop_row.nil?
        ncm = p["ncm"].to_s
        it["ncm_chapter"] = ncm[0, 2]
        it["ncm_generic"] = ncm == "00000000" || ncm == "00"
        it["ncm_valid"] = !@catalog.lookup("ncm", [ncm]).nil? if @catalog.lookup("ncm", ["__present__"]) || ncm_table?
        it["is_service"] = it.key?("issqn")
        if (icms = it["icms"])
          icms["situation_code"] = icms["cst"] || icms["csosn"]
          icms["situation_field"] = icms["cst"] ? "cst" : icms["csosn"] ? "csosn" : "absent"
          icms["origin_category"] = %w[1 2 6 7].include?(icms["origin"]) ? "imported" : "domestic"
          icms["highlights_icms"] = dec.(icms["amount"]) > 0
          if icms["base_mode"]
            red = dec.(icms["base_reduction_pct"])
            icms["expected_base_amount"] = fmt((net * (1 - red / 100)).round(2, BigDecimal::ROUND_HALF_UP))
            icms["expected_base_reliable"] = icms["base_mode"] == "3"
          end
          icms["expected_amount"] = fmt((dec.(icms["base_amount"]) * dec.(icms["rate"]) / 100).round(2, BigDecimal::ROUND_HALF_UP)) if icms["base_amount"] && icms["rate"]
          table = icms["cst"] ? "cst_icms" : "csosn"
          icms["taxation_kind"] = @catalog.lookup(table, [icms["situation_code"].to_s])&.dig("taxation_kind") || "unknown"
        end
        if (st = it["icms_st"])
          st["highlights_st"] = dec.(st["amount"]) > 0
          st["has_withheld_st"] = st.dig("withheld", "amount").present?
        end
        it["has_difal"] = it.key?("icms_uf_dest")
        %w[pis cofins].each do |k|
          next unless (x = it[k])
          x["expected_amount"] = fmt((dec.(x["base_amount"]) * dec.(x["rate"]) / 100).round(2, BigDecimal::ROUND_HALF_UP)) if x["base_amount"] && x["rate"]
          x["taxation_kind"] = @catalog.lookup("cst_pis_cofins", [x["cst"].to_s])&.dig("taxation_kind") || "unknown"
        end
        if (ipi = it["ipi"]) && ipi["base_amount"] && ipi["rate"]
          ipi["expected_amount"] = fmt((dec.(ipi["base_amount"]) * dec.(ipi["rate"]) / 100).round(2, BigDecimal::ROUND_HALF_UP))
        end
        it["ibs_cbs"] ||= { "present" => false }
        if it["ibs_cbs"]["present"]
          year = d["reference_date"].to_s[0, 4]
          sched = { "cbs" => @catalog.lookup("ibs_cbs_schedule", [year, "cbs"])&.dig("rate"),
                    "ibs_uf" => @catalog.lookup("ibs_cbs_schedule", [year, "ibs_uf"])&.dig("rate"),
                    "ibs_city" => @catalog.lookup("ibs_cbs_schedule", [year, "ibs_city"])&.dig("rate") }.compact
          it["ibs_cbs"]["schedule_rates"] = sched unless sched.empty?
          %w[cbs ibs_uf ibs_city].each do |k|
            g = it["ibs_cbs"][k]
            next unless g && g["effective_rate"] && it["ibs_cbs"]["base_amount"]
            g["expected_amount"] = fmt((dec.(it["ibs_cbs"]["base_amount"]) * dec.(g["effective_rate"]) / 100).round(2, BigDecimal::ROUND_HALF_UP))
          end
        end
      end

      def ncm_table? = (@ncm_table = Catalog::ReferenceTable.exists?(code: "ncm")) if @ncm_table.nil?

      def nature(d)
        purpose = d.dig("issuance", "purpose")
        return purpose if %w[complementary adjustment].include?(purpose)
        by_amount = d["items"].group_by { |i| i["cfop_nature"] }.transform_values { |is| is.sum { |i| BigDecimal(i["net_amount"]) } }
        predominant = by_amount.max_by { |_, v| v }&.first || "other"
        return predominant if purpose == "return" && predominant.end_with?("_return")
        return (d["operation"]["direction"] == "inbound" ? "sale_return" : "purchase_return") if purpose == "return"
        predominant
      end

      def totals(d)
        t = d["totals"] ||= {}
        sums = Hash.new(BigDecimal("0"))
        d["items"].each do |i|
          next if i.dig("product", "included_in_total") == false
          sums["products"] += BigDecimal((i.dig("product", "gross_amount") || "0").to_s)
          sums["discount"] += BigDecimal((i.dig("product", "discount") || "0").to_s)
          sums["freight"] += BigDecimal((i.dig("product", "freight") || "0").to_s)
          sums["icms_base"] += BigDecimal((i.dig("icms", "base_amount") || "0").to_s)
          sums["icms"] += BigDecimal((i.dig("icms", "amount") || "0").to_s)
          sums["icms_st"] += BigDecimal((i.dig("icms_st", "amount") || "0").to_s)
          sums["ipi"] += BigDecimal((i.dig("ipi", "amount") || "0").to_s)
          sums["pis"] += BigDecimal((i.dig("pis", "amount") || "0").to_s)
          sums["cofins"] += BigDecimal((i.dig("cofins", "amount") || "0").to_s)
          sums["ibs"] += BigDecimal((i.dig("ibs_cbs", "ibs", "amount") || "0").to_s)
          sums["cbs"] += BigDecimal((i.dig("ibs_cbs", "cbs", "amount") || "0").to_s)
          sums["is"] += BigDecimal((i.dig("is", "amount") || "0").to_s)
        end
        t["items_sum"] = sums.transform_values { |v| fmt(v) }
        t["totals_mismatch"] = sums.each_with_object({}) do |(k, v), h|
          next unless t[k]
          diff = BigDecimal(t[k].to_s) - v
          h[k] = fmt(diff) unless diff.zero?
        end
      end

      def status_state(code)
        case code
        when "100", "150" then "authorized"
        when "110", "301", "302", "303" then "denied"
        when nil then "no_protocol"
        else "rejected"
        end
      end

      def fmt(v) = v.round(2, BigDecimal::ROUND_HALF_UP).to_s("F").then { |s| s.include?(".") ? s.sub(/(\.\d)$/, '\10') : "#{s}.00" }
    end
  end
end
