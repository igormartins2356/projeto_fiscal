module Rules
  module Dsl
    # Mini-linguagem aritmética (DSL_RULES.md §4). Parser recursivo próprio; sem eval.
    # Gramática: or > and > not > comparison > additive > multiplicative > unary > primary
    class Calc
      TOKEN = /\s*(?:(\d+\.\d+|\d+)|([A-Za-z_][A-Za-z0-9_\.\[\]]*)|(==|!=|<=|>=|<|>|\(|\)|,|\+|-|\*|\/|%))/
      FUNCTIONS = %w[round abs min max sum coalesce year month days_between len opt].freeze
      KEYWORDS = %w[and or not true false null].freeze

      def self.evaluate(expr, ctx) = new(expr, ctx).evaluate
      # Tokens da expressão, para a validação estática (Validator confere os identificadores)
      def self.tokens(expr) = new(expr, {}).tokens

      def initialize(expr, ctx)
        @ctx = ctx
        @tokens = tokenize(expr.to_s)
        @pos = 0
      end

      def evaluate
        v = parse_or
        raise EvaluationError, "unexpected token #{peek.inspect} in calc" unless peek.nil?
        v
      end

      attr_reader :tokens

      private

      def tokenize(src)
        tokens = []
        rest = src.strip
        until rest.empty?
          m = TOKEN.match(rest)
          raise EvaluationError, "invalid calc syntax near #{rest[0, 20].inspect}" unless m && m.begin(0).zero?
          tokens << (m[1] ? [:num, BigDecimal(m[1])] : m[2] ? [:id, m[2]] : [:op, m[3]])
          rest = m.post_match.lstrip
        end
        tokens
      end

      def peek = @tokens[@pos]
      def next! = (@pos += 1; @tokens[@pos - 1])
      def accept(type, val = nil)
        t = peek
        return nil unless t && t[0] == type && (val.nil? || t[1] == val)
        next!
      end

      # Sem curto-circuito: o lado direito precisa ser consumido mesmo quando o esquerdo já decide,
      # senão os tokens sobram na fila e "true or false" vira "unexpected token".
      def parse_or
        l = parse_and
        while accept(:id, "or")
          r = parse_and
          l = truthy(l) || truthy(r)
        end
        l
      end

      def parse_and
        l = parse_not
        while accept(:id, "and")
          r = parse_not
          l = truthy(l) && truthy(r)
        end
        l
      end

      def parse_not
        return !truthy(parse_not) if accept(:id, "not")
        parse_comparison
      end

      def parse_comparison
        l = parse_additive
        while (op = %w[== != <= >= < >].find { |o| accept(:op, o) })
          r = parse_additive
          l = case op
              when "==" then Value.equal?(l, r)
              when "!=" then !Value.equal?(l, r)
              else
                c = Value.compare(l, r)
                raise EvaluationError, "incomparable values in calc" if c.nil?
                { "<" => c < 0, "<=" => c <= 0, ">" => c > 0, ">=" => c >= 0 }.fetch(op)
              end
        end
        l
      end

      def parse_additive
        l = parse_multiplicative
        while (op = %w[+ -].find { |o| accept(:op, o) })
          r = parse_multiplicative
          l = op == "+" ? dec(l) + dec(r) : dec(l) - dec(r)
        end
        l
      end

      def parse_multiplicative
        l = parse_unary
        while (op = %w[* / %].find { |o| accept(:op, o) })
          r = parse_unary
          l = case op
              when "*" then dec(l) * dec(r)
              when "/" then (raise EvaluationError, "division by zero" if dec(r).zero?; dec(l) / dec(r))
              else dec(l) % dec(r)
              end
        end
        l
      end

      def parse_unary
        return -dec(parse_unary) if accept(:op, "-")
        parse_primary
      end

      def parse_primary
        if accept(:op, "(")
          v = parse_or
          accept(:op, ")") or raise EvaluationError, "missing ) in calc"
          return v
        end
        if (t = accept(:num)) then return t[1] end
        if (t = accept(:id))
          name = t[1]
          case name
          when "true" then return true
          when "false" then return false
          when "null" then return nil
          end
          return call(name) if FUNCTIONS.include?(name) && accept(:op, "(")
          v = Path.fetch(@ctx, name)
          raise EvaluationError, "absent field #{name} in calc" if Path.absent?(v)
          return v
        end
        raise EvaluationError, "unexpected end of calc"
      end

      def call(name)
        args = []
        unless accept(:op, ")")
          loop do
            args << (%w[sum opt].include?(name) && peek&.first == :id ? next![1] : parse_or)
            break if accept(:op, ")")
            accept(:op, ",") or raise EvaluationError, "expected , in #{name}()"
          end
        end
        case name
        when "round" then dec(args[0]).round((args[1] || 0).to_i, BigDecimal::ROUND_HALF_UP)
        when "abs" then dec(args[0]).abs
        when "min" then args.map { |a| dec(a) }.min
        when "max" then args.map { |a| dec(a) }.max
        when "coalesce" then args.find { |a| !a.nil? }
        when "opt" then (v = Path.fetch(@ctx, args[0].to_s); Path.absent?(v) ? nil : v)
        when "len" then Array(args[0]).size
        when "year" then Value.to_date(args[0]).year
        when "month" then Value.to_date(args[0]).month
        when "days_between" then (Value.to_date(args[1]) - Value.to_date(args[0])).to_i
        when "sum"
          list_path, _, field = args[0].to_s.rpartition(".")
          list = Path.fetch(@ctx, list_path)
          raise EvaluationError, "sum over non-list #{list_path}" unless list.is_a?(Array)
          list.sum(BigDecimal("0")) { |el| v = Path.fetch(el, field); Path.absent?(v) ? BigDecimal("0") : dec(v) }
        end
      end

      def dec(v) = Value.to_decimal(v)
      def truthy(v) = !(v.nil? || v == false)
    end
  end
end
