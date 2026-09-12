module Scenario
  # Validação server-side mínima do cenário (o formulário valida com zod; aqui é a garantia antes de publicar).
  class Validator
    REGIMES = %w[simples_nacional simples_nacional_excess lucro_presumido lucro_real mei].freeze
    UFS = %w[AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO].freeze
    ACTIVITIES = %w[commerce industry service rural mixed].freeze
    IBS_CBS_REGIMES = %w[regular simples_nacional_opt_in].freeze
    BENEFIT_KINDS = %w[reduced_base presumed_credit deferral exemption suspension].freeze
    NCM_PATTERN = /\A\d{2,8}\*?\z/
    ISO_DATE = /\A\d{4}-\d{2}-\d{2}\z/

    def initialize(data) = @d = data || {}

    def errors
      e = []
      e << "regime tributário inválido" unless REGIMES.include?(@d["tax_regime"])
      e << "UF inválida" unless UFS.include?(@d["uf"])
      e << "atividade obrigatória" if Array(@d["activity"]).empty?
      invalid = Array(@d["activity"]) - ACTIVITIES
      e << "atividade inválida: #{invalid.join(', ')}" if invalid.any?
      e << "regime de PIS/COFINS obrigatório" unless %w[simples cumulative non_cumulative].include?(@d.dig("pis_cofins", "regime"))
      e << "Simples Nacional exige PIS/COFINS 'simples'" if @d["tax_regime"].to_s.start_with?("simples") && @d.dig("pis_cofins", "regime") != "simples"
      ibs_cbs = @d.dig("ibs_cbs", "regime")
      e << "regime de IBS/CBS inválido" if ibs_cbs.present? && !IBS_CBS_REGIMES.include?(ibs_cbs)
      # exceção de ST e benefício são "regra fiscal do cliente": sem base legal e vigência o motor não pode usá-los (DSL_RULES §7)
      Array(@d.dig("st", "overrides")).each_with_index do |o, i|
        label = "exceção de ST ##{i + 1}"
        e << "#{label}: NCM inválido (2 a 8 dígitos, sufixo * permitido)" unless o.is_a?(Hash) && o["ncm"].to_s.match?(NCM_PATTERN)
        next unless o.is_a?(Hash)
        e << "#{label}: informe se a ST se aplica (true/false)" unless [true, false].include?(o["applies"])
        e.concat(legal_errors(o, label))
      end
      Array(@d["benefits"]).each_with_index do |b, i|
        label = "benefício ##{i + 1}"
        unless b.is_a?(Hash)
          e << "#{label}: formato inválido"
          next
        end
        e << "#{label}: tipo inválido (#{BENEFIT_KINDS.join(', ')})" unless BENEFIT_KINDS.include?(b["kind"])
        e << "#{label}: percentual inválido" if b.key?("pct") && !valid_pct?(b["pct"])
        bad_ncm = Array(b.dig("applies_to", "ncm")).reject { |n| n.to_s.match?(NCM_PATTERN) }
        e << "#{label}: NCM inválido em applies_to (#{bad_ncm.join(', ')})" if bad_ncm.any?
        bad_cfop = Array(b.dig("applies_to", "cfop")).reject { |c| c.to_s.match?(/\A\d{4}\z/) }
        e << "#{label}: CFOP inválido em applies_to (#{bad_cfop.join(', ')})" if bad_cfop.any?
        e.concat(legal_errors(b, label))
      end
      e
    end

    private

    def legal_errors(h, label)
      e = []
      e << "#{label}: informe a base legal" if h["legal_basis"].to_s.strip.length < 3
      e << "#{label}: início de vigência inválido (AAAA-MM-DD)" unless h["effective_from"].to_s.match?(ISO_DATE) && valid_date?(h["effective_from"])
      if h["effective_until"].present?
        if !h["effective_until"].to_s.match?(ISO_DATE) || !valid_date?(h["effective_until"])
          e << "#{label}: fim de vigência inválido (AAAA-MM-DD)"
        elsif h["effective_from"].to_s.match?(ISO_DATE) && h["effective_until"] < h["effective_from"]
          e << "#{label}: fim da vigência deve ser posterior ao início"
        end
      end
      e
    end

    def valid_date?(v)
      Date.iso8601(v.to_s)
      true
    rescue Date::Error
      false
    end

    def valid_pct?(v)
      return false unless v.to_s.match?(/\A\d{1,3}(\.\d{1,4})?\z/)
      BigDecimal(v.to_s) <= 100
    end
  end
end
