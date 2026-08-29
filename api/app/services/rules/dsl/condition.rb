module Rules
  module Dsl
    # Avalia condições (DSL_RULES.md §3). Retorna true/false; levanta EvaluationError quando não avaliável.
    module Condition
      OPS = %w[eq neq in not_in gt gte lt lte between approx present absent regex starts_with ends_with contains
               length_eq length_between empty not_empty].freeze

      def self.evaluate(cond, ctx)
        return true if cond.nil?
        raise EvaluationError, "condition must be an object" unless cond.is_a?(Hash)

        return cond["all"].all? { |c| evaluate(c, ctx) } if cond.key?("all")
        return cond["any"].any? { |c| evaluate(c, ctx) } if cond.key?("any")
        return !evaluate(cond["not"], ctx) if cond.key?("not")
        if cond.key?("if")
          return evaluate(cond["if"], ctx) ? evaluate(cond["then"], ctx) : (cond.key?("else") ? evaluate(cond["else"], ctx) : true)
        end
        return quantifier(cond, ctx) if %w[every some none count].any? { |q| cond.key?(q) }
        return lookup_present(cond, ctx) if cond.key?("lookup")

        compare(cond, ctx)
      end

      def self.compare(cond, ctx)
        field, op = cond["field"], cond["op"]
        raise EvaluationError, "missing field/op in #{cond.inspect}" unless field && op
        raise EvaluationError, "unknown op #{op}" unless OPS.include?(op)

        actual = Path.fetch(ctx, field)
        absent = Path.absent?(actual)
        return absent if op == "absent"
        return !absent if op == "present"

        value = Value.resolve(cond["value"], ctx)
        if absent
          return value.nil? if op == "eq"
          return !value.nil? if op == "neq"
          return Array(value).include?(nil) if op == "in"
          raise EvaluationError, "field #{field} absent for op #{op}"
        end
        raise EvaluationError, "value for #{field} resolved to absent" if Path.absent?(value)

        case op
        when "eq" then Value.equal?(actual, value)
        when "neq" then !Value.equal?(actual, value)
        when "in" then Array(value).any? { |v| Value.equal?(actual, v) }
        when "not_in" then Array(value).none? { |v| Value.equal?(actual, v) }
        when "gt" then Value.compare(actual, value) > 0
        when "gte" then Value.compare(actual, value) >= 0
        when "lt" then Value.compare(actual, value) < 0
        when "lte" then Value.compare(actual, value) <= 0
        when "between" then Value.compare(actual, value[0]) >= 0 && Value.compare(actual, value[1]) <= 0
        when "approx"
          a, b = Value.to_decimal(actual), Value.to_decimal(value)
          if cond.key?("tolerance_pct")
            (a - b).abs <= b.abs * Value.to_decimal(Value.resolve(cond["tolerance_pct"], ctx)) / 100
          else
            (a - b).abs <= Value.to_decimal(Value.resolve(cond.fetch("tolerance", "0"), ctx))
          end
        when "regex" then actual.to_s.match?(Regexp.new(value.to_s))
        when "starts_with" then actual.to_s.start_with?(value.to_s)
        when "ends_with" then actual.to_s.end_with?(value.to_s)
        when "contains" then actual.is_a?(Array) ? actual.include?(value) : actual.to_s.include?(value.to_s)
        when "length_eq" then actual.to_s.length == value.to_i
        when "length_between" then actual.to_s.length.between?(value[0].to_i, value[1].to_i)
        when "empty" then actual.respond_to?(:empty?) ? actual.empty? : actual.nil?
        when "not_empty" then actual.respond_to?(:empty?) ? !actual.empty? : !actual.nil?
        end
      end

      def self.quantifier(cond, ctx)
        q = %w[every some none count].find { |k| cond.key?(k) }
        list = Path.fetch(ctx, cond[q])
        raise EvaluationError, "quantifier over absent list #{cond[q]}" if Path.absent?(list)
        raise EvaluationError, "quantifier over non-list #{cond[q]}" unless list.is_a?(Array)
        as = cond.fetch("as", "it")
        matches = list.select { |el| evaluate(cond["where"], ctx.merge(as => el)) }
        case q
        when "every" then matches.size == list.size
        when "some" then matches.any?
        when "none" then matches.empty?
        when "count" then compare({ "field" => "__count", "op" => cond["op"], "value" => cond["value"] }, ctx.merge("__count" => matches.size))
        end
      end

      def self.lookup_present(cond, ctx)
        Let.lookup(cond, ctx) != Path::ABSENT
      end
    end
  end
end
