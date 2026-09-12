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
      # Alíquotas-limite de PIS vêm da regra publicada vigente na nota mais recente (nunca literais aqui)
      ref_date = docs.map(&:reference_date).compact.max || Date.current
      pis_ref = pis_rate_reference(ref_date)
      pis_kinds = dist(items.select { |i| i.dig("pis", "cst_direction") == "outbound" }.map { |i| i.dig("pis", "taxation_kind") })
      pc = pis_cofins_regime(items, pis_kinds, pis_ref)

      crt = dist(docs.map { |d| d.data.dig("issuer", "crt") })
      regime_map = { "1" => "simples_nacional", "2" => "simples_nacional_excess", "3" => nil, "4" => "mei" }
      top_crt, share = crt.first
      if top_crt
        if top_crt == "3"
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
      # Classificação vem do catálogo `cfop` (own_production/nature), não de lista de códigos: 6108/5104 etc. também são venda
      industry = share_of(items) { |i| i["cfop_own_production"] == true }
      commerce = share_of(items) { |i| %w[sale export].include?(i["cfop_nature"]) && i["cfop_own_production"] != true }
      activity = []
      activity << "industry" if industry > 0.15
      activity << "commerce" if commerce > 0.15
      activity << "service" if items.any? { |i| i["is_service"] }
      activity = ["commerce"] if activity.empty?
      f["activity"] = { "value" => activity, "confidence" => [(industry + commerce), 0.95].min.round(2), "evidence" => "CFOP de produção própria (catálogo): #{pct(industry)}; CFOP de venda/revenda: #{pct(commerce)}" }

      nfce_share = docs.count { |d| d.model == "65" }.fdiv(docs.size)
      f["uses_nfce"] = { "value" => nfce_share > 0, "confidence" => 0.95, "evidence" => "#{pct(nfce_share)} das notas são NFC-e" }
      final_share = docs.count { |d| d.data.dig("operation", "final_consumer") || d.data.dig("recipient", "person_type") == "individual" }.fdiv(docs.size)
      f["sells_to_final_consumer"] = { "value" => final_share > 0.1 || nfce_share > 0, "confidence" => 0.85, "evidence" => "#{pct(final_share)} das notas a consumidor final/CPF" }
      f["exports"] = { "value" => cfops.any? { |c, _| c.start_with?("7") }, "confidence" => 0.95, "evidence" => "CFOP 7xxx #{cfops.any? { |c, _| c.start_with?('7') } ? 'presente' : 'ausente'}" }

      st_share = share_of(items) { |i| i.dig("icms_st", "highlights_st") || i.dig("icms", "taxation_kind") == "st_withheld" || %w[substitute substituted].include?(i["cfop_st_role"]) }
      f["st"] = { "value" => { "source" => "catalog", "applies" => st_share > 0.05, "overrides" => [] }, "confidence" => (st_share > 0.05 ? [st_share * 2, 0.95].min : 0.8).round(2), "evidence" => "#{pct(st_share)} dos itens com ST destacada/retida" }

      if pc.nil? && pis_ref.nil? && pis_kinds.first&.first == "taxed"
        # Sem referência de alíquota vigente não há como separar cumulativo × não cumulativo: sem palpite (regime ausente)
        f["pis_cofins"] = { "value" => {}, "confidence" => 0.0, "evidence" => "#{pis_cofins_evidence(items)}; regra PISCOFINS.RATE.REGIME sem versão publicada vigente em #{ref_date}: regime não inferido" }
      else
        f["pis_cofins"] = { "value" => { "regime" => pc || (top_crt == "3" ? "cumulative" : "simples") }, "confidence" => pc ? 0.85 : 0.4, "evidence" => pis_cofins_evidence(items) }
      end

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

    PIS_RATE_RULE = "PISCOFINS.RATE.REGIME"

    # Lê da regra publicada as alíquotas de PIS esperadas (ramo `then` = regime do `if`, `else` = o outro) e a tolerância.
    # nil quando não há versão vigente na data — a inferência então não chuta o regime.
    def pis_rate_reference(date)
      # source_type "platform": a alíquota-limite é lei federal. Sem o filtro, uma regra de mesmo code publicada
      # por OUTRA firma (o model só garante unicidade de code+version) seria lida na inferência deste cliente.
      rule = Rules::Rule.where(code: PIS_RATE_RULE, state: "published", source_type: "platform").effective_on(date).order(version: :desc).first
      assert = rule&.body&.dig("assert") or return nil
      then_regime = assert.dig("if", "value").to_s
      pick = ->(branch) { Array(assert.dig(branch, "all")).find { |c| c["field"] == "item.pis.rate" } }
      then_c, else_c = pick.("then"), pick.("else")
      return nil unless then_c && else_c && %w[non_cumulative cumulative].include?(then_regime)
      other_regime = then_regime == "non_cumulative" ? "cumulative" : "non_cumulative"
      { then_regime => BigDecimal(then_c["value"].to_s), other_regime => BigDecimal(else_c["value"].to_s), "tolerance" => BigDecimal((then_c["tolerance"] || "0").to_s) }
    end

    def pis_cofins_regime(items, pis_kinds, ref)
      top, _ = pis_kinds.first
      return "simples" if top == "other"
      return nil unless top == "taxed" && ref
      rates = dist(items.select { |i| i.dig("pis", "cst_direction") == "outbound" && i.dig("pis", "taxation_kind") == "taxed" }.map { |i| i.dig("pis", "rate") })
      rate = BigDecimal((rates.first&.first || "0").to_s)
      %w[non_cumulative cumulative].find { |r| (rate - ref[r]).abs <= ref["tolerance"] }
    end

    def pis_cofins_evidence(items)
      csts = dist(items.map { |i| i.dig("pis", "cst") }).first(3).map { |c, s| "CST #{c}: #{pct(s)}" }.join(", ")
      "PIS #{csts}"
    end
  end
end
