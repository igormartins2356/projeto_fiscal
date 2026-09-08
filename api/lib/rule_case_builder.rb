# Constrói documentos canônicos mínimos para casos de teste de regras (seeds e specs).
# Uso: RuleCaseBuilder.doc(item: { icms: { csosn: "900" } }, doc: { issuance: { purpose: "return" } }, items: [...])
module RuleCaseBuilder
  module_function

  # nil no override remove a chave (ausência canônica), em vez de gravar null
  def deep_merge(a, b)
    a.merge(b) { |_, x, y| x.is_a?(Hash) && y.is_a?(Hash) ? deep_merge(x, y) : y }.reject { |_, v| v.nil? }
  end

  def item(overrides = {})
    base = {
      "number" => 1,
      "product" => { "code" => "A1", "description" => "Produto A", "ncm" => "84713012", "cfop" => "5102", "commercial_unit" => "UN", "commercial_quantity" => "2.0000", "commercial_unit_price" => "500.00", "gross_amount" => "1000.00", "discount" => "0.00", "included_in_total" => true },
      "icms" => { "group" => "ICMSSN102", "origin" => "0", "csosn" => "102" },
      "pis" => { "group" => "PISOutr", "cst" => "49", "base_amount" => "0.00", "rate" => "0.00", "amount" => "0.00" },
      "cofins" => { "group" => "COFINSOutr", "cst" => "49", "base_amount" => "0.00", "rate" => "0.00", "amount" => "0.00" },
      "ibs_cbs" => { "present" => true, "cst" => "000", "class_code" => "000001", "base_amount" => "1000.00",
                     "ibs_uf" => { "rate" => "0.10", "effective_rate" => "0.10", "amount" => "1.00" }, "ibs_city" => { "rate" => "0.00", "effective_rate" => "0.00", "amount" => "0.00" },
                     "ibs" => { "amount" => "1.00" }, "cbs" => { "rate" => "0.90", "effective_rate" => "0.90", "amount" => "9.00" } }
    }
    deep_merge(base, overrides.deep_stringify_keys)
  end

  # Regime normal (CST) em vez de Simples
  def normal_item(overrides = {})
    item(deep_merge({ "icms" => { "group" => "ICMS00", "csosn" => nil, "cst" => "00", "base_mode" => "3", "base_amount" => "1000.00", "rate" => "18.00", "amount" => "180.00" },
                      "pis" => { "group" => "PISAliq", "cst" => "01", "base_amount" => "1000.00", "rate" => "0.65", "amount" => "6.50" },
                      "cofins" => { "group" => "COFINSAliq", "cst" => "01", "base_amount" => "1000.00", "rate" => "3.00", "amount" => "30.00" } }, overrides.deep_stringify_keys))
  end

  def doc(items: nil, item: {}, doc: {}, normal: false)
    its = items || [normal ? normal_item(item) : item(item)]
    sums = ->(path) { its.sum(BigDecimal("0")) { |i| BigDecimal((i.dig(*path) || "0").to_s) } }
    fmt = ->(v) { v.round(2).to_s("F").sub(/\.(\d)$/, '.\10') }
    base = {
      "schema_version" => 1, "kind" => "nfe", "model" => "55", "access_key" => "35260312345678000190550010000012341000012345", "layout_version" => "4.00", "environment" => "production",
      "xml_hash" => SecureRandom.hex(32),
      "issuance" => { "issued_at" => "2026-03-14T10:22:00-03:00", "series" => "1", "number" => 1234, "purpose" => "normal", "emission_type" => "normal" },
      "operation" => { "direction_declared" => "outbound", "scope" => "intrastate", "final_consumer" => false, "nature_text" => "VENDA" },
      "references" => [],
      "issuer" => { "cnpj" => "12345678000190", "legal_name" => "Cliente Exemplo", "ie" => "123456789012", "crt" => normal ? "3" : "1", "uf" => "SP", "address" => { "uf" => "SP", "city_code" => "3550308" } },
      "recipient" => { "cnpj" => "99887766000155", "legal_name" => "Destinatario", "ie_indicator" => "taxpayer", "ie" => "987654321098", "uf" => "SP", "address" => { "uf" => "SP" } },
      "totals" => { "products" => fmt.(sums.(%w[product gross_amount])), "discount" => fmt.(sums.(%w[product discount])), "icms_base" => fmt.(sums.(%w[icms base_amount])), "icms" => fmt.(sums.(%w[icms amount])),
                    "icms_st" => fmt.(sums.(%w[icms_st amount])), "ipi" => fmt.(sums.(%w[ipi amount])), "pis" => fmt.(sums.(%w[pis amount])), "cofins" => fmt.(sums.(%w[cofins amount])), "freight" => "0.00",
                    "total" => fmt.(sums.(%w[product gross_amount]) - sums.(%w[product discount]) + sums.(%w[icms_st amount]) + sums.(%w[ipi amount])), "approx_taxes" => "150.00" },
      "payments" => [{ "timing" => "cash", "method" => "01", "amount" => "1000.00" }],
      "additional_info" => { "complementary" => "DOCUMENTO EMITIDO POR ME OU EPP OPTANTE PELO SIMPLES NACIONAL" },
      "protocol" => { "number" => "135260000000001", "status_code" => "100", "received_at" => "2026-03-14T10:22:30-03:00" },
      "items" => its
    }
    deep_merge(base, doc.deep_stringify_keys)
  end
end
