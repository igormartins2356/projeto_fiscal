module Rules
  module Dsl
    # Bloco "let": lookups e cálculos pré-avaliados que viram variáveis do contexto.
    module Let
      def self.apply(lets, ctx)
        Array(lets).reduce(ctx) do |c, spec|
          name = spec["as"] or raise EvaluationError, "let entry without 'as'"
          # calc/ref sobre campo ausente → variável ausente (a regra decide com present/absent em applies_when)
          value = if spec.key?("lookup") then lookup(spec, c)
                  elsif spec.key?("calc")
                    begin
                      Calc.evaluate(spec["calc"], c)
                    rescue EvaluationError => e
                      raise unless e.message.start_with?("absent field")
                      Path::ABSENT
                    end
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
