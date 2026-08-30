module Scenario
  # Validação server-side mínima do cenário (o formulário valida com zod; aqui é a garantia antes de publicar).
  class Validator
    REGIMES = %w[simples_nacional simples_nacional_excess lucro_presumido lucro_real mei].freeze
    UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze

    def initialize(data) = @d = data || {}

    def errors
      e = []
      e << "regime tributário inválido" unless REGIMES.include?(@d["tax_regime"])
      e << "UF inválida" unless UFS.include?(@d["uf"])
      e << "atividade obrigatória" if Array(@d["activity"]).empty?
      e << "regime de PIS/COFINS obrigatório" unless %w[simples cumulative non_cumulative].include?(@d.dig("pis_cofins", "regime"))
      e << "Simples Nacional exige PIS/COFINS 'simples'" if @d["tax_regime"].to_s.start_with?("simples") && @d.dig("pis_cofins", "regime") != "simples"
      e
    end
  end
end
