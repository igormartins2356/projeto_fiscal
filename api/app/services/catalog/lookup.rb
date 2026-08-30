module Catalog
  # Lookup de tabela de referência vigente numa data, com precedência client > firm > platform.
  # Cache por (tabela, versão) dentro de uma execução.
  class Lookup
    def initialize(date:, firm_id: nil, client_id: nil, overrides_enabled: true)
      @date = date
      @firm_id = firm_id
      @client_id = client_id
      @overrides_enabled = overrides_enabled
      @tables = {}
      @versions_used = {}
    end

    attr_reader :versions_used

    class TableUnavailable < StandardError; end

    # Retorna Hash com os dados da linha (+ "_source") ou nil.
    # strict: true (usado pela DSL) levanta TableUnavailable quando a tabela não tem versão vigente na data —
    # assim a regra vira evaluation_error em vez de apontar erro ao contador por falta de dado.
    def lookup(table_code, key, strict: false)
      key = Array(key).map(&:to_s)
      override = @overrides_enabled ? find_override(table_code, key) : nil
      return override if override

      table = table_for(table_code)
      if table.nil?
        raise TableUnavailable, "tabela '#{table_code}' sem versão publicada vigente em #{@date}" if strict
        return nil
      end
      table[:rows][key]
    end

    private

    def table_for(code)
      @tables.fetch(code) do
        ref = Catalog::ReferenceTable.find_by(code:)
        version = ref&.version_effective_on(@date)
        @tables[code] = if version
          @versions_used[code] = version.id
          rows = version.rows.each_with_object({}) do |r, h|
            next if r.effective_from && r.effective_from > @date
            next if r.effective_until && r.effective_until < @date
            h[r.key] = r.data.merge("_source" => "platform", "_legal_basis" => r.legal_basis)
          end
          { rows: }
        end
      end
    end

    def find_override(code, key)
      return nil unless @firm_id || @client_id
      ref = Catalog::ReferenceTable.find_by(code:) or return nil
      scope = Catalog::ReferenceRowOverride.where(reference_table_id: ref.id, key:)
                .where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", @date, @date)
      client = @client_id && scope.find_by(source_type: "client", source_id: @client_id)
      return client.data.merge("_source" => "client", "_override_id" => client.id) if client
      firm = @firm_id && scope.find_by(source_type: "firm", source_id: @firm_id)
      return firm.data.merge("_source" => "firm", "_override_id" => firm.id) if firm
      nil
    end
  end
end
