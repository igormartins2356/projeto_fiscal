module Catalog
  module Importers
    # Importa o leiaute da NF-e/NFC-e para o catálogo, a partir dos esquemas oficiais
    # (`Sefaz::LayoutExtractor`). É o equivalente, para a NF-e, do que `sped_layout` já é para a EFD.
    #
    # A chave é o **caminho** do campo, não a tag: `CNPJ` existe em emitente, destinatário e
    # transportador, e `vBC` em quase todo grupo de imposto. Guardar por tag confundiria campos
    # diferentes com o mesmo nome.
    class NfeLayout
      TABLE_CODE = "nfe_layout".freeze
      SOURCE = "Portal da NF-e — Pacote de Liberação dos Esquemas XML (seção Esquemas XML)".freeze
      LEGAL_BASIS = "Manual de Orientação ao Contribuinte, Anexo I — Leiaute da NF-e".freeze

      def initialize(table = nil, package_path: nil)
        @table = table || find_or_create_table
        @package_path = package_path
      end

      def call(user: nil)
        fields = Sefaz::LayoutExtractor.call(package_path: @package_path)
        raise ArgumentError, "esquema sem campos de leiaute" if fields.empty?

        version = nil
        Catalog::ReferenceVersion.transaction do
          last = @table.versions.order(version: :desc).first
          version = @table.versions.create!(
            version: (last&.version || 0) + 1, state: "draft", source_url: SOURCE, imported_by: user,
            effective_from: [@table.versions.published.minimum(:effective_from), Date.current].compact.min,
            notes: "#{fields.size} campos do leiaute 4.00 (#{fields.count { |f| f.enumerations.present? }} " \
                   "com enumeração, #{fields.count(&:pattern)} com padrão de formato)"
          )
          Catalog::ReferenceRow.insert_all!(fields.map do |field|
            { reference_version_id: version.id, key: [field.path], data: field.to_h, legal_basis: LEGAL_BASIS }
          end)
        end
        { version:, imported: fields.size,
          groups: fields.count { |f| fields.map(&:parent_path).include?(f.path) },
          with_enumerations: fields.count { |f| f.enumerations.present? } }
      end

      private

      def find_or_create_table
        Catalog::ReferenceTable.find_or_create_by!(code: TABLE_CODE) do |t|
          t.name = "Leiaute da NF-e (campos do XML)"
          t.key_names = %w[path]
          t.key_arity = 1
          t.source_class = "A"
          t.source_url = SOURCE
        end
      end
    end
  end
end
