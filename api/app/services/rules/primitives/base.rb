module Rules
  module Primitives
    # Primitiva = validador nativo sem valor fiscal embutido. Subclasses declaram scope e params_schema.
    class Base
      REGISTRY = {}

      def self.register(name) = REGISTRY[name] = self
      def self.find(name)
        REGISTRY[name] || "Rules::Primitives::#{name.to_s.camelize}".safe_constantize.tap { |k| k&.register(name) } ||
          raise(EvaluationError, "unknown primitive #{name}")
      end
      def self.scope(s = nil) = s ? (@scope = s) : @scope
      def self.params_schema(h = nil) = h ? (@params_schema = h) : (@params_schema || {})

      def initialize(params, ctx)
        @params = (self.class.params_schema.transform_values { |v| v[:default] }).merge(params || {})
        @ctx = ctx
      end

      # Retorna array de Hash: { target: {document:, item_number:}, evidence: {}, vars: {} }
      def call = raise(NotImplementedError)
    end
  end
end
