module Catalog
  module Importers
    # Monofásicos/alíquotas concentradas de PIS/COFINS por NCM (classe B): listas legais por posição/código,
    # expandidas para NCMs de 8 dígitos usando a tabela `ncm` publicada.
    # Cobertura: Lei 10.147/00 (medicamentos e perfumaria), Lei 13.097/15 (bebidas frias), Lei 9.718/98 art. 4º + 10.560/02 (combustíveis).
    # PENDENTE: Lei 10.485/02 (autopeças, anexos I/II — lista específica) — importar quando curada.
    GROUPS = [
      { branch: "medicamentos", legal_basis: "Lei 10.147/2000, art. 1º I 'a'", prefixes: %w[3001 3003 3004 300510 300630 300660], except: %w[30039056 30049046] },
      { branch: "perfumaria", legal_basis: "Lei 10.147/2000, art. 1º I 'b'", prefixes: %w[330300 3304 3305 3306 3307 34011190 34012010 96032100], except: [] },
      { branch: "bebidas_frias", legal_basis: "Lei 13.097/2015, art. 14", prefixes: %w[2201 2202 2203 21069010], except: [] },
      { branch: "combustiveis", legal_basis: "Lei 9.718/98 art. 4º; Lei 10.560/02", prefixes: %w[271012 271019 271119 220710 220720], except: [] }
    ].freeze

    class PisCofinsSpecial
      def initialize(table = Catalog::ReferenceTable.find_or_create_by!(code: "pis_cofins_special") { |t| t.name = "PIS/COFINS — NCM monofásicos/alíquotas concentradas"; t.key_names = ["ncm"]; t.key_arity = 1; t.source_class = "B"; t.source_url = "https://www.planalto.gov.br/ccivil_03/leis/l10147.htm" })
        @table = table
      end

      def call(user: nil)
        ncm_version = Catalog::ReferenceTable.find_by!(code: "ncm").version_effective_on(Date.current) or raise ArgumentError, "importe e publique a tabela ncm antes"
        all_ncms = ncm_version.rows.pluck(:key).map(&:first)
        rows = GROUPS.flat_map do |g|
          all_ncms.select { |n| g[:prefixes].any? { |p| n.start_with?(p) } && g[:except].none? { |e| n.start_with?(e) } }
                  .map { |n| { key: [n], data: { "kind" => "single_phase", "branch" => g[:branch], "legal_basis" => g[:legal_basis] }, legal_basis: g[:legal_basis] } }
        end
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: Date.new(2015, 1, 1), state: "draft", imported_by: user,
                                          notes: "#{rows.size} NCMs expandidos das listas legais (medicamentos, perfumaria, bebidas frias, combustíveis); autopeças pendente")
        Catalog::ReferenceRow.insert_all!(rows.map { |r| r.merge(reference_version_id: version.id) })
        { version:, imported: rows.size }
      end
    end
  end
end
