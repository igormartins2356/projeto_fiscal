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
      @row_override_ids_used = []
    end

    attr_reader :versions_used, :row_override_ids_used

    # Há versão publicada vigente na data?
    def table_available?(code)
      !table_for(code).nil?
    end

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
      bucket = overrides[[code, key]] or return nil
      chosen = bucket["client"] || bucket["firm"] or return nil
      @row_override_ids_used << chosen[:id] unless @row_override_ids_used.include?(chosen[:id])
      chosen[:data].merge("_source" => chosen[:source_type], "_override_id" => chosen[:id])
    end

    # Todos os overrides vigentes de (firma, cliente) numa query só: Audit::Coverage e as derivações
    # chamam lookup por item, e três queries por chamada viravam milhares por run.
    # A ordem (effective_from desc, id desc) torna determinística a escolha quando há mais de um vigente.
    def overrides
      @overrides ||= begin
        model = Catalog::ReferenceRowOverride
        sources = []
        sources << model.where(source_type: "client", source_id: @client_id) if @client_id
        sources << model.where(source_type: "firm", source_id: @firm_id) if @firm_id
        scope = model.where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", @date, @date)
                     .merge(sources.reduce(:or))
        scope.joins(:reference_table).order(effective_from: :desc, id: :desc)
             .pluck("reference_tables.code", :key, :data, :source_type, :id)
             .each_with_object({}) do |(code, key, data, source_type, id), h|
          bucket = (h[[code, Array(key).map(&:to_s)]] ||= {})
          bucket[source_type] ||= { id:, data:, source_type: }
        end
      end
    end
  end
end
