module Catalog
  module Importers
    # Monofásicos/alíquotas concentradas de PIS/COFINS por NCM (classe B): listas legais por posição/código,
    # expandidas para NCMs de 8 dígitos usando a tabela `ncm` publicada.
    # Os grupos (prefixos, base legal e vigência de cada lei) são dado: db/data/pis_cofins_special_groups.yml.
    class PisCofinsSpecial
      GROUPS_PATH = Rails.root.join("db/data/pis_cofins_special_groups.yml")

      def initialize(table = Catalog::ReferenceTable.find_or_create_by!(code: "pis_cofins_special") { |t| t.name = "PIS/COFINS — NCM monofásicos/alíquotas concentradas"; t.key_names = ["ncm"]; t.key_arity = 1; t.source_class = "B"; t.source_url = "https://www.planalto.gov.br/ccivil_03/leis/l10147.htm" })
        @table = table
      end

      def call(user: nil)
        ncm_version = Catalog::ReferenceTable.find_by!(code: "ncm").version_effective_on(Date.current) or raise ArgumentError, "importe e publique a tabela ncm antes"
        all_ncms = ncm_version.rows.pluck(:key).map(&:first)
        rows = groups.flat_map do |g|
          all_ncms.select { |n| g["prefixes"].any? { |p| n.start_with?(p) } && g["except"].none? { |e| n.start_with?(e) } }
                  .map { |n| { key: [n], data: { "kind" => "single_phase", "branch" => g["branch"], "legal_basis" => g["legal_basis"] }, legal_basis: g["legal_basis"], effective_from: g["effective_from"] } }
        end
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: groups.map { |g| g["effective_from"] }.min, state: "draft", imported_by: user,
                                          notes: "#{rows.size} NCMs expandidos das listas legais (#{groups.map { |g| g['branch'] }.join(', ')}); autopeças pendente")
        Catalog::ReferenceRow.insert_all!(rows.map { |r| r.merge(reference_version_id: version.id) })
        { version:, imported: rows.size }
      end

      private

      def groups
        @groups ||= YAML.safe_load_file(GROUPS_PATH).each { |g| g["effective_from"] = Date.parse(g["effective_from"]) }
      end
    end
  end
end
