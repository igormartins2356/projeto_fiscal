module Rules
  module Dsl
    # Resolve o lado direito de uma comparação: literal, {"ref": path}, {"calc": expr}, {"param": name}.
    module Value
      DECIMAL = /\A-?\d+(\.\d+)?\z/

      def self.resolve(spec, ctx)
        case spec
        when Hash
          if spec.key?("ref")   then Path.fetch(ctx, spec["ref"])
          elsif spec.key?("calc") then Calc.evaluate(spec["calc"], ctx)
          elsif spec.key?("param") then Path.fetch(ctx, "params.#{spec['param']}")
          else spec
          end
        else spec
        end
      end

      def self.numeric?(v) = v.is_a?(Numeric) || (v.is_a?(String) && v.match?(DECIMAL))

      def self.to_decimal(v)
        return v if v.is_a?(BigDecimal)
        return BigDecimal(v.to_s) if v.is_a?(Numeric)
        return BigDecimal(v) if v.is_a?(String) && v.match?(DECIMAL)
        raise EvaluationError, "not numeric: #{v.inspect}"
      end

      def self.to_date(v)
        case v
        when Date, DateTime, Time then v.to_date
        when String then Date.parse(v)
        else raise EvaluationError, "not a date: #{v.inspect}"
        end
      rescue ArgumentError
        raise EvaluationError, "not a date: #{v.inspect}"
      end

      # Comparação tolerante a tipos: decimal x string numérica compara numericamente.
      def self.compare(a, b)
        if numeric?(a) && numeric?(b) then to_decimal(a) <=> to_decimal(b)
        elsif (a.is_a?(Date) || a.is_a?(Time)) || (b.is_a?(Date) || b.is_a?(Time)) then to_date(a) <=> to_date(b)
        else a <=> b
        end
      end

      def self.equal?(a, b)
        return a == b if a.nil? || b.nil? || [a, b].any? { |x| x == true || x == false }
        c = compare(a, b)
        c.nil? ? a == b : c.zero?
      end
    end
  end
end
