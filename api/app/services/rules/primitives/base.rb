module Rules
  module Primitives
    # Primitiva = validador nativo sem valor fiscal embutido. Subclasses declaram scope e params_schema.
    class Base
      REGISTRY = {}

      def self.register(name) = REGISTRY[name] = self
      def self.find(name)
        REGISTRY[name] || begin
          klass = "Rules::Primitives::#{name.to_s.camelize}".safe_constantize
          # "base" resolveria para esta classe abstrata e explodiria com NotImplementedError no meio do run
          raise(EvaluationError, "unknown primitive #{name}") unless klass.is_a?(Class) && klass < Base
          klass.register(name)
          klass
        end
      end
      def self.scope(s = nil) = s ? (@scope = s) : @scope
      def self.params_schema(h = nil) = h ? (@params_schema = h) : (@params_schema || {})
      # Variáveis que a primitiva expõe em `vars` (usáveis em message/group_by); usado pela validação estática
      def self.vars(*names) = names.any? ? (@vars = names.map(&:to_s)) : (@vars || [])

      def initialize(params, ctx)
        defaults = self.class.params_schema.to_h { |k, v| [k.to_s, v[:default]] }
        @params = defaults.merge((params || {}).transform_keys(&:to_s))
        @ctx = ctx
      end

      # Retorna array de Hash: { target: {document:, item_number:}, evidence: {}, vars: {} }
      def call = raise(NotImplementedError)

      private

      # Param sem default: valor fiscal (prazo, COD_SIT, modelo) é dado da regra, não do código.
      def param!(name)
        v = @params[name]
        raise EvaluationError, "primitiva #{self.class.name.demodulize.underscore}: parâmetro '#{name}' obrigatório e não informado na regra" if v.nil? || (v.respond_to?(:empty?) && v.empty?)
        v
      end

      def dec(v) = Dsl::Value.to_decimal(v)
    end
  end
end
