module Rules
  module Dsl
    # Renderiza "{{path}}" na mensagem; coleta os caminhos referenciados (para evidence).
    module Template
      PATTERN = /\{\{\s*([A-Za-z_][A-Za-z0-9_\.\[\]]*)\s*\}\}/

      def self.render(text, ctx)
        text.to_s.gsub(PATTERN) do
          v = Path.fetch(ctx, Regexp.last_match(1))
          Path.absent?(v) ? "—" : display(v)
        end
      end

      def self.paths(text) = text.to_s.scan(PATTERN).flatten.uniq

      # Mensagem é lida pelo contador: booleano vira sim/não (evidence e group_key guardam o valor técnico).
      def self.display(v)
        case v
        when true then "sim"
        when false then "não"
        else format(v)
        end
      end

      def self.format(v)
        case v
        when BigDecimal then v.to_s("F")
        when Array then v.map { |x| format(x) }.join(", ")
        when Hash then v.map { |k, x| "#{k}: #{format(x)}" }.join(", ")   # sem isso sai o inspect do Ruby
        else v.to_s
        end
      end
    end
  end
end
