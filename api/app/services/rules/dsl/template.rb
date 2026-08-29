module Rules
  module Dsl
    # Renderiza "{{path}}" na mensagem; coleta os caminhos referenciados (para evidence).
    module Template
      PATTERN = /\{\{\s*([A-Za-z_][A-Za-z0-9_\.\[\]]*)\s*\}\}/

      def self.render(text, ctx)
        text.to_s.gsub(PATTERN) do
          v = Path.fetch(ctx, Regexp.last_match(1))
          Path.absent?(v) ? "—" : format(v)
        end
      end

      def self.paths(text) = text.to_s.scan(PATTERN).flatten.uniq

      def self.format(v)
        case v
        when BigDecimal then v.to_s("F")
        when Array then v.join(", ")
        else v.to_s
        end
      end
    end
  end
end
