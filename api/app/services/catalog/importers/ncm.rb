require "net/http"

module Catalog
  module Importers
    # NCM do Siscomex (classe A): JSON público com vigência por código.
    class Ncm
      URL = "https://portalunico.siscomex.gov.br/classif/api/publico/nomenclatura/download/json?perfil=PUBLICO"

      def initialize(table = Catalog::ReferenceTable.find_or_create_by!(code: "ncm") { |t| t.name = "NCM"; t.key_names = ["ncm"]; t.key_arity = 1; t.source_class = "A"; t.source_url = URL })
        @table = table
      end

      # Baixa (ou usa `json`), cria versão draft e retorna { version:, imported:, diff: }
      def call(json: nil, user: nil)
        payload = json || JSON.parse(Net::HTTP.get(URI(URL)))
        items = payload["Nomenclaturas"] || payload["nomenclaturas"] || []
        rows = items.filter_map do |n|
          code = n["Codigo"].to_s.delete(".")
          next unless code.length == 8
          { key: [code], data: { "description" => n["Descricao"].to_s.strip, "chapter" => code[0, 2] }, effective_from: br_date(n["Data_Inicio"]), effective_until: br_date(n["Data_Fim"]),
            legal_basis: [n["Tipo_Ato_Ini"], n["Numero_Ato_Ini"], n["Ano_Ato_Ini"]].compact.join(" ").presence }
        end
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: rows.filter_map { |r| r[:effective_from] }.min || Date.current, state: "draft", source_url: URL, imported_by: user,
                                          notes: "Siscomex #{payload['Data_Ultima_Atualizacao']} — #{rows.size} códigos de 8 dígitos")
        rows.each_slice(5000) { |slice| Catalog::ReferenceRow.insert_all!(slice.map { |r| r.merge(reference_version_id: version.id) }) }
        { version:, imported: rows.size }
      end

      private

      def br_date(s)
        return nil if s.blank? || s.to_s.start_with?("31/12/9999")
        Date.strptime(s, "%d/%m/%Y")
      rescue ArgumentError
        nil
      end
    end
  end
end
