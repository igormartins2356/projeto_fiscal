module Audit
  # Estatísticas prontas para o escopo `scenario` (DSL_RULES.md §5)
  class Stats
    # itens de nota cancelada/denegada/rejeitada não representam a operação do cliente
    EXCLUDED_STATES = %w[cancelled denied rejected].freeze

    def initialize(docs)
      @items = docs.select { |d| d["role"] == "issuer" && !EXCLUDED_STATES.include?(d.dig("status", "state")) }
                   .flat_map { |d| (d["items"] || []).map { |i| { "item" => i, "doc" => d } } }
    end

    def distribution(path)
      values = @items.map { |c| v = Rules::Dsl::Path.fetch(c, path); Rules::Dsl::Path.absent?(v) ? nil : v }.compact
      return {} if values.empty?
      values.tally.transform_values { |n| (BigDecimal(n) / values.size).round(4) }
    end

    # fração dos itens AVALIÁVEIS que satisfazem a condição; item inavaliável não conta como "não satisfaz"
    def share(condition)
      matches, evaluated = tally(condition)
      return BigDecimal(0) if evaluated.zero?
      BigDecimal(matches) / evaluated
    end

    def count(condition) = tally(condition).first

    def unevaluable(condition) = @items.size - tally(condition).last

    private

    def tally(condition)
      matches = evaluated = 0
      @items.each do |c|
        v = Rules::Dsl::Condition.evaluate(condition, c)
        evaluated += 1
        matches += 1 if v
      rescue Rules::EvaluationError
        next
      end
      [matches, evaluated]
    end
  end
end
