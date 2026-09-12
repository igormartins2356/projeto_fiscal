module Audit
  # Relatório de cobertura do catálogo: o que as notas do período consultaram e a base ainda não cobre.
  # Alimenta a fila de curadoria (st_uf por demanda, com base legal por linha — decisão de 31/08/2026).
  # Acumula em fatias porque o run resolve o catálogo por vigência: cada fatia tem o seu próprio Lookup.
  class Coverage
    def initialize
      @st_missing = Hash.new(0)
      @internal_ncm = Hash.new(0)
    end

    def add(canonicals, catalog)
      canonicals.each do |doc|
        next unless doc["role"] == "issuer" && doc.dig("status", "state") == "authorized"
        dest = doc.dig("operation", "destination_uf").to_s
        next if dest.blank? || dest == "EX"
        (doc["items"] || []).each do |it|
          next if it["is_service"]
          ncm = it.dig("product", "ncm").to_s
          next unless ncm.match?(/\A\d{8}\z/)
          @st_missing[[dest, ncm]] += 1 if !it.key?("st_applicable_by_catalog") && catalog.table_available?("st_uf")
          # alíquota interna específica por NCM ainda não curada (só a geral "*")
          @internal_ncm[[dest, ncm]] += 1 if catalog.lookup("icms_internal_rate", [dest, ncm]).nil? && it.dig("icms", "taxation_kind").in?(%w[taxed taxed_with_st reduced_base])
        end
      end
      self
    end

    def result
      {
        "st_uf" => @st_missing.sort_by { |_, n| -n }.first(50).map { |(uf, ncm), n| { "uf" => uf, "ncm" => ncm, "items" => n } },
        "st_uf_total_missing" => @st_missing.values.sum,
        "icms_internal_rate_ncm" => @internal_ncm.sort_by { |_, n| -n }.first(50).map { |(uf, ncm), n| { "uf" => uf, "ncm" => ncm, "items" => n } },
        "icms_internal_rate_ncm_total" => @internal_ncm.values.sum
      }
    end
  end
end
