module Rules
  module Dsl
    # Bloco "let": lookups e cálculos pré-avaliados que viram variáveis do contexto.
    module Let
      def self.apply(lets, ctx)
        Array(lets).reduce(ctx) do |c, spec|
          name = spec["as"] or raise EvaluationError, "let entry without 'as'"
          value = if spec.key?("lookup") then lookup(spec, c)
                  elsif spec.key?("calc") then Calc.evaluate(spec["calc"], c)
                  elsif spec.key?("ref") then Path.fetch(c, spec["ref"])
                  else raise EvaluationError, "let entry must have lookup/calc/ref"
                  end
          c.merge(name => value)
        end
      end

      def self.lookup(spec, ctx)
        catalog = ctx["catalog"] or raise EvaluationError, "no catalog in context"
        key = Array(spec["key"]).map { |k| Value.resolve(k, ctx) }
        return Path::ABSENT if key.any? { |k| Path.absent?(k) || k.nil? }
        catalog.lookup(spec["lookup"], key, strict: true) || Path::ABSENT
      rescue Catalog::Lookup::TableUnavailable => e
        raise EvaluationError, e.message
      end
    end
  end
end
