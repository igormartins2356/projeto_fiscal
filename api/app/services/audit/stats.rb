module Audit
  # Estatísticas prontas para o escopo `scenario` (DSL_RULES.md §5)
  class Stats
    def initialize(docs) = @items = docs.select { |d| d["role"] == "issuer" }.flat_map { |d| (d["items"] || []).map { |i| { "item" => i, "doc" => d } } }

    def distribution(path)
      values = @items.map { |c| v = Rules::Dsl::Path.fetch(c, path); Rules::Dsl::Path.absent?(v) ? nil : v }.compact
      return {} if values.empty?
      values.tally.transform_values { |n| (n.fdiv(values.size)).round(4) }
    end

    def share(condition)
      return 0 if @items.empty?
      @items.count { |c| Rules::Dsl::Condition.evaluate(condition, c) rescue false }.fdiv(@items.size)
    end

    def count(condition) = @items.count { |c| Rules::Dsl::Condition.evaluate(condition, c) rescue false }
  end
end
