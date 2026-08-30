module Scenario
  # Inferência assistida (ARQUITETURA.md §14): propõe cenário a partir das notas emitidas do cliente.
  # Saída: { fields: { campo => { value:, confidence: 0..1, evidence: "texto" } }, sample: {...} }
  class Inference
    def initialize(client, months: 6)
      @client = client
      @since = months.months.ago.to_date
    end

    def call
      docs = @client.documents.fiscal.where(role: "issuer", status_state: "authorized").where("reference_date >= ?", @since).includes(:items).to_a
      return { fields: {}, sample: { documents: 0 }, message: "nenhuma nota emitida autorizada no período" } if docs.empty?
      items = docs.flat_map { |d| d.items.map { |i| i.data } }
      f = {}

      crt = dist(docs.map { |d| d.data.dig("issuer", "crt") })
      regime_map = { "1" => "simples_nacional", "2" => "simples_nacional_excess", "3" => nil, "4" => "mei" }
      top_crt, share = crt.first
      if top_crt
        if top_crt == "3"
          pc = pis_cofins_regime(items)
          f["tax_regime"] = { "value" => pc == "non_cumulative" ? "lucro_real" : "lucro_presumido", "confidence" => (share * (pc ? 0.8 : 0.5)).round(2),
                              "evidence" => "#{pct(share)} das notas com CRT 3 (regime normal); PIS/COFINS sugere #{pc || 'indefinido'}" }
        else
          f["tax_regime"] = { "value" => regime_map[top_crt], "confidence" => share.round(2), "evidence" => "#{pct(share)} das notas com CRT #{top_crt}" }
        end
      end

      f["uf"] = { "value" => @client.uf, "confidence" => 1.0, "evidence" => "cadastro do cliente" }
      f["icms_taxpayer"] = { "value" => docs.any? { |d| d.data.dig("issuer", "ie").present? }, "confidence" => 0.9, "evidence" => "IE presente no emitente" }

      ipi_share = share_of(items) { |i| BigDecimal((i.dig("ipi", "amount") || "0").to_s) > 0 }
      f["ipi_taxpayer"] = { "value" => ipi_share > 0.05, "confidence" => (ipi_share > 0.05 ? [ipi_share * 2, 0.95].min : 0.8).round(2), "evidence" => "#{pct(ipi_share)} dos itens com IPI destacado" }

      natures = dist(items.map { |i| i["cfop_nature"] })
      cfops = dist(items.map { |i| i.dig("product", "cfop") })
      industry = cfops.select { |c, _| %w[5101 6101 7101 5401 6401].include?(c) }.sum(&:last)
      commerce = cfops.select { |c, _| %w[5102 6102 7102 5403 6403 5405 5404].include?(c) }.sum(&:last)
      activity = []
      activity << "industry" if industry > 0.15
      activity << "commerce" if commerce > 0.15
      activity << "service" if items.any? { |i| i["is_service"] }
      activity = ["commerce"] if activity.empty?
      f["activity"] = { "value" => activity, "confidence" => [(industry + commerce), 0.95].min.round(2), "evidence" => "CFOP 5101/6101 (produção própria): #{pct(industry)}; 5102/6102 (revenda): #{pct(commerce)}" }

      nfce_share = docs.count { |d| d.model == "65" }.fdiv(docs.size)
      f["uses_nfce"] = { "value" => nfce_share > 0, "confidence" => 0.95, "evidence" => "#{pct(nfce_share)} das notas são NFC-e" }
      final_share = docs.count { |d| d.data.dig("operation", "final_consumer") || d.data.dig("recipient", "person_type") == "individual" }.fdiv(docs.size)
      f["sells_to_final_consumer"] = { "value" => final_share > 0.1 || nfce_share > 0, "confidence" => 0.85, "evidence" => "#{pct(final_share)} das notas a consumidor final/CPF" }
      f["exports"] = { "value" => cfops.any? { |c, _| c.start_with?("7") }, "confidence" => 0.95, "evidence" => "CFOP 7xxx #{cfops.any? { |c, _| c.start_with?('7') } ? 'presente' : 'ausente'}" }

      st_share = share_of(items) { |i| i.dig("icms_st", "highlights_st") || %w[60 500].include?(i.dig("icms", "situation_code")) }
      f["st"] = { "value" => { "source" => "catalog", "overrides" => [] }, "confidence" => 0.6, "evidence" => "#{pct(st_share)} dos itens com ST destacada/retida — confira a tabela de ST da UF" }

      pc = pis_cofins_regime(items)
      f["pis_cofins"] = { "value" => { "regime" => pc || (top_crt == "3" ? "cumulative" : "simples") }, "confidence" => pc ? 0.85 : 0.4, "evidence" => pis_cofins_evidence(items) }

      ibs_share = share_of(items) { |i| i.dig("ibs_cbs", "present") }
      f["ibs_cbs"] = { "value" => { "regime" => "regular" }, "confidence" => 0.5, "evidence" => "#{pct(ibs_share)} dos itens com grupo IBS/CBS" }

      { fields: f, sample: { documents: docs.size, items: items.size, since: @since, natures: natures.first(5).to_h, top_cfops: cfops.first(8).to_h } }
    end

    private

    def dist(values)
      v = values.compact
      return [] if v.empty?
      v.tally.transform_values { |n| n.fdiv(v.size) }.sort_by { |_, s| -s }
    end

    def share_of(items) = items.empty? ? 0.0 : items.count { |i| yield(i) }.fdiv(items.size)
    def pct(v) = "#{(v * 100).round}%"

    def pis_cofins_regime(items)
      csts = dist(items.map { |i| i.dig("pis", "cst") })
      top, _ = csts.first
      return "simples" if top == "49"
      return nil unless top == "01"
      rates = dist(items.select { |i| i.dig("pis", "cst") == "01" }.map { |i| i.dig("pis", "rate") })
      rate = BigDecimal((rates.first&.first || "0").to_s)
      rate >= BigDecimal("1.65") ? "non_cumulative" : rate > 0 ? "cumulative" : nil
    end

    def pis_cofins_evidence(items)
      csts = dist(items.map { |i| i.dig("pis", "cst") }).first(3).map { |c, s| "CST #{c}: #{pct(s)}" }.join(", ")
      "PIS #{csts}"
    end
  end
end
