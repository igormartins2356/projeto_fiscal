module Rules
  # Validação estática de uma definição de regra (DSL_RULES.md §12). errors bloqueiam; warnings só informam.
  class Validator
    OPS = Dsl::Condition::OPS
    attr_reader :errors, :warnings

    def initialize(definition)
      @d = definition.deep_stringify_keys
      @errors = []
      @warnings = []
      @vars = %w[params] + Array(@d["let"]).map { |l| l["as"] }.compact
      if (name = @d.dig("primitive", "name"))
        @vars += (Primitives::Base.find(name).vars rescue [])
      end
    end

    def valid?
      check_shape
      check_let
      walk_condition(@d["applies_when"], "applies_when") if @d["applies_when"]
      walk_condition(@d["assert"], "assert") if @d["assert"]
      check_primitive if @d["primitive"]
      check_message
      @errors.empty?
    end

    private

    def scope = @d["scope"]

    def check_shape
      @errors << "code obrigatório (PREFIX.SUBJECT.DETAIL)" unless @d["code"].to_s.match?(/\A[A-Z0-9_]+(\.[A-Z0-9_]+)+\z/)
      @errors << "scope inválido" unless Rules::Rule::SCOPES.include?(scope)
      @errors << "severity inválida" unless Rules::Rule::SEVERITIES.include?(@d["severity"])
      @errors << "informe exatamente um de assert ou primitive" unless [@d["assert"], @d["primitive"]].compact.size == 1
      @errors << "message obrigatória" if @d["message"].blank?
      @errors << "effective_from obrigatório" if @d["effective_from"].blank?
    end

    def check_let
      Array(@d["let"]).each_with_index do |l, i|
        @errors << "let[#{i}] precisa de 'as'" if l["as"].blank?
        if l["lookup"]
          table = Catalog::ReferenceTable.find_by(code: l["lookup"])
          if table.nil? then @errors << "let[#{i}]: tabela '#{l['lookup']}' não existe no Catalog"
          elsif table.key_arity != Array(l["key"]).size then @errors << "let[#{i}]: tabela '#{l['lookup']}' espera chave com #{table.key_arity} parte(s)"
          end
          Array(l["key"]).each { |k| check_path(k["ref"], "let[#{i}].key") if k.is_a?(Hash) && k["ref"] }
        elsif l["calc"]
          check_calc(l["calc"], "let[#{i}]")
        elsif l["ref"]
          check_path(l["ref"], "let[#{i}]")
        else
          @errors << "let[#{i}] precisa de lookup, calc ou ref"
        end
      end
    end

    def walk_condition(c, where)
      return @errors << "#{where}: condição deve ser objeto" unless c.is_a?(Hash)
      if c["all"] || c["any"]
        list = c["all"] || c["any"]
        return @errors << "#{where}: all/any deve ser lista" unless list.is_a?(Array)
        list.each_with_index { |x, i| walk_condition(x, "#{where}[#{i}]") }
      elsif c["not"] then walk_condition(c["not"], "#{where}.not")
      elsif c["if"]
        walk_condition(c["if"], "#{where}.if"); walk_condition(c["then"], "#{where}.then"); walk_condition(c["else"], "#{where}.else") if c["else"]
      elsif (q = %w[every some none count].find { |k| c[k] })
        check_path(c[q], where)
        @vars << (c["as"] || "it")
        walk_condition(c["where"], "#{where}.where")
        @vars.pop
        @errors << "#{where}: count exige op/value" if q == "count" && (c["op"].nil? || !c.key?("value"))
      elsif c["lookup"]
        check_let_like(c, where)
      else
        @errors << "#{where}: field obrigatório" if c["field"].blank?
        @errors << "#{where}: op '#{c['op']}' desconhecido" unless OPS.include?(c["op"])
        check_path(c["field"], where) if c["field"]
        check_value(c["value"], where) if c.key?("value")
        @errors << "#{where}: approx exige tolerance ou tolerance_pct" if c["op"] == "approx" && !c.key?("tolerance") && !c.key?("tolerance_pct")
      end
    end

    def check_let_like(c, where)
      table = Catalog::ReferenceTable.find_by(code: c["lookup"])
      @errors << "#{where}: tabela '#{c['lookup']}' não existe" unless table
    end

    def check_value(v, where)
      return unless v.is_a?(Hash)
      check_path(v["ref"], where) if v["ref"]
      check_calc(v["calc"], where) if v["calc"]
      @errors << "#{where}: param '#{v['param']}' não declarado em params" if v["param"] && !@d.dig("params", v["param"])
    end

    def check_path(path, where)
      case CanonicalSchema.check(path, scope:, extra_vars: @vars)
      when :unknown_root then @errors << "#{where}: '#{path}' não está disponível no escopo #{scope}"
      when :unknown_path then @warnings << "#{where}: caminho '#{path}' não consta no dicionário canônico (confira CANONICO.md)"
      end
    end

    def check_calc(expr, where)
      Dsl::Calc.new(expr, {}).send(:tokenize, expr).each { |t| check_path(t[1], where) if t[0] == :id && !Dsl::Calc::FUNCTIONS.include?(t[1]) && !Dsl::Calc::KEYWORDS.include?(t[1]) }
    rescue EvaluationError => e
      @errors << "#{where}: calc inválido (#{e.message})"
    end

    def check_primitive
      name = @d.dig("primitive", "name")
      klass = Primitives::Base.find(name)
      @errors << "primitiva '#{name}' é de escopo #{klass.scope}, regra é #{scope}" if klass.scope != scope
      unknown = (@d.dig("primitive", "params") || {}).keys.map(&:to_s) - klass.params_schema.keys.map(&:to_s)
      @errors << "primitiva '#{name}': params desconhecidos #{unknown.join(', ')}" if unknown.any?
    rescue EvaluationError => e
      @errors << e.message
    end

    def check_message
      Dsl::Template.paths(@d["message"]).each { |p| check_path(p, "message") }
    end
  end
end
