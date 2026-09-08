module Rules
  module Primitives
    # Erros estruturais coletados pelo parser (leiaute como dado): campo faltando, CNPJ divergente.
    class SpedStructure < Base
      register "sped_structure"
      scope "period"
      params_schema({})
      vars :line, :record, :error

      def call
        file = @ctx["fiscal_file"] or return []
        Array(file.dig("info", "errors")).map do |e|
          { target: {}, evidence: { "line" => e["line"], "record" => e["record"], "error" => e["error"] },
            vars: { "line" => e["line"], "record" => e["record"], "error" => e["error"] } }
        end
      end
    end
  end
end
