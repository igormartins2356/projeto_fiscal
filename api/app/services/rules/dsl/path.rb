module Rules
  module Dsl
    # Resolve caminhos pontilhados ("item.icms.rate", "doc.references[0].resolved") num contexto Hash.
    # Retorna ABSENT quando qualquer segmento não existe (CANONICO.md §0: ausência ≠ null).
    module Path
      ABSENT = Object.new.freeze
      SEGMENT = /\A([A-Za-z_][A-Za-z0-9_]*)(?:\[(\d+)\])?\z/

      def self.absent?(v) = v.equal?(ABSENT)

      def self.fetch(context, path)
        path.to_s.split(".").reduce(context) do |node, seg|
          return ABSENT if node.nil? || absent?(node)
          m = SEGMENT.match(seg) or raise EvaluationError, "invalid path segment #{seg.inspect} in #{path.inspect}"
          key, idx = m[1], m[2]
          value = case node
                  when Hash then node.key?(key) ? node[key] : (node.key?(key.to_sym) ? node[key.to_sym] : ABSENT)
                  else node.respond_to?(key) ? node.public_send(key) : ABSENT
                  end
          if idx
            return ABSENT unless value.is_a?(Array) && value.size > idx.to_i
            value = value[idx.to_i]
          end
          value
        end
      end
    end
  end
end
