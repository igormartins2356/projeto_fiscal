module Catalog
  module Importers
    # Importa a planilha oficial de classificação tributária do IBS e da CBS (Portal da NF-e, seção
    # Diversos). Ela tem duas abas e alimenta duas tabelas:
    #
    # - `ibs_cbs_class` (aba "cClass"): a classificação por `cClassTrib`, que o projeto já tinha vindo
    #   de raspagem da página da SVRS. A planilha acrescenta o que faltava: a **vigência de cada
    #   classificação** (hoje o catálogo não tem, então classificação nova ou revogada não é tratada
    #   por data), o tipo de alíquota e os indicadores de grupo do XML.
    # - `ibs_cbs_cst` (aba "CST"): por situação tributária, quais grupos o XML pode trazer. É a matriz
    #   que permite dizer "CST 010 não admite grupo de redução" sem escrever regra caso a caso.
    #
    # O formato de `ibs_cbs_class` é preservado campo por campo, porque as regras publicadas já o
    # consomem; o que a planilha traz de novo é acrescentado.
    class IbsCbsTables
      SOURCE = "Portal da NF-e — Tabela de Classificação Tributária do IBS e CBS, seção Diversos".freeze
      LEGAL_BASIS = "Lei Complementar 214/2025".freeze
      # A aba de CST não traz vigência própria; o regime do IBS e da CBS começa em 01/01/2026
      # (LC 214/2025). Usar a data de hoje faria documento anterior não encontrar a tabela.
      REGIME_START = Date.new(2026, 1, 1).freeze

      # Indicadores de grupo do XML, por classificação.
      CLASS_INDICATORS = %w[ind_gTribRegular ind_gCredPresOper ind_gMonoPadrao ind_gMonoReten
                            ind_gMonoRet ind_gMonoDif ind_gpBioDiferenca ind_gEstornoCred].freeze
      # Indicadores de qual documento fiscal aceita a classificação.
      DOCUMENTS = { "indNFe" => "nfe", "indNFCe" => "nfce", "indNFeABI" => "nfe_abi", "indCTe" => "cte",
                    "indCTeOS" => "cte_os", "indBPe" => "bpe", "indNF3e" => "nf3e", "indNFSe" => "nfse",
                    "indNFCom" => "nfcom", "indNFAg" => "nfag", "indNFGas" => "nfgas",
                    "indDUIMP" => "duimp", "indDIR" => "dir", "indDERE" => "dere" }.freeze

      def initialize(path: nil)
        @path = path
      end

      def call(user: nil)
        sheets = Sefaz::SpreadsheetReader.call(source_path)
        classes = import_classes(sheet_with(sheets, "cClassTrib"), user:)
        csts = import_csts(sheet_with(sheets, "ind_gIBSCBS"), user:)
        { classes:, csts: }
      end

      private

      def sheet_with(sheets, coluna)
        sheets.find { |s| s.rows.first.to_a.any? { |c| normalize(c) == normalize(coluna) } } or
          raise ArgumentError, "planilha sem a aba que tem a coluna #{coluna}"
      end

      # A SEFAZ publicou uma coluna como "ind_ gCredPresIBSZFM", com espaço no meio do nome.
      def normalize(nome) = nome.to_s.gsub(/\s+/, "").downcase

      def fetch(record, coluna)
        chave = record.keys.find { |k| normalize(k) == normalize(coluna) }
        chave ? record[chave].to_s.strip : ""
      end

      def import_classes(sheet, user:)
        table = Catalog::ReferenceTable.find_by!(code: "ibs_cbs_class")
        rows = sheet.records.filter_map do |record|
          code = fetch(record, "cClassTrib")
          next unless code.match?(/\A\d{6}\z/)
          {
            key: [code],
            effective_from: Sefaz::SpreadsheetReader.to_date(fetch(record, "dIniVig")),
            effective_until: Sefaz::SpreadsheetReader.to_date(fetch(record, "dFimVig")),
            data: class_data(record)
          }
        end
        raise ArgumentError, "aba de cClassTrib sem nenhuma classificação" if rows.empty?
        publish_draft(table, rows, user:, notes: "#{rows.size} classificações com vigência, da planilha oficial")
      end

      def class_data(record)
        {
          "cst" => fetch(record, "CST-IBS/CBS"),
          "cst_name" => fetch(record, "Descrição CST-IBS/CBS").presence,
          "short_name" => fetch(record, "Nome cClassTrib").presence,
          "description" => fetch(record, "Descrição cClassTrib").presence,
          "reduction_ibs_pct" => decimal(fetch(record, "pRedIBS")),
          "reduction_cbs_pct" => decimal(fetch(record, "pRedCBS")),
          "rate_type" => fetch(record, "Tipo de Alíquota").presence,
          "tp_rbsn" => fetch(record, "tpRBSN").presence,
          "legal_basis" => fetch(record, "LC 214/25").presence || LEGAL_BASIS,
          "annex" => fetch(record, "ANEXO").presence,
          "link" => fetch(record, "Link").presence,
          "group_indicators" => CLASS_INDICATORS.to_h { |c| [c.sub("ind_g", "").sub("ind_", ""), flag(record, c)] },
          "indicators" => DOCUMENTS.to_h { |coluna, nome| [nome, flag(record, coluna)] }
        }.compact
      end

      def import_csts(sheet, user:)
        table = Catalog::ReferenceTable.find_or_create_by!(code: "ibs_cbs_cst") do |t|
          t.name = "CST do IBS/CBS e grupos admitidos"
          t.key_names = %w[cst]
          t.key_arity = 1
          t.source_class = "A"
          t.source_url = SOURCE
        end
        colunas = sheet.rows.first.select { |c| normalize(c).start_with?("ind_") }
        rows = sheet.records.filter_map do |record|
          cst = fetch(record, "CST-IBS/CBS")
          next unless cst.match?(/\A\d{3}\z/)
          { key: [cst], effective_from: REGIME_START, effective_until: nil,
            data: { "description" => fetch(record, "Descrição CST-IBS/CBS").presence,
                    "groups" => colunas.to_h { |c| [normalize(c).sub("ind_g", "").sub("ind_", ""), flag(record, c)] } }.compact }
        end
        raise ArgumentError, "aba de CST sem nenhuma situação tributária" if rows.empty?
        publish_draft(table, rows, user:, notes: "#{rows.size} CSTs com os grupos admitidos no XML")
      end

      def publish_draft(table, rows, user:, notes:)
        version = nil
        Catalog::ReferenceVersion.transaction do
          last = table.versions.order(version: :desc).first
          anterior = table.versions.published.minimum(:effective_from)
          inicio = rows.filter_map { |r| r[:effective_from] }.min
          version = table.versions.create!(
            version: (last&.version || 0) + 1, state: "draft", source_url: SOURCE, imported_by: user,
            # Não pode começar depois da publicada, senão o período que ela cobria fica sem tabela.
            effective_from: [inicio, anterior, Date.current].compact.min, notes:
          )
          Catalog::ReferenceRow.insert_all!(rows.map do |r|
            { reference_version_id: version.id, key: r[:key], data: r[:data],
              effective_from: r[:effective_from], effective_until: r[:effective_until],
              legal_basis: r[:data]["legal_basis"].presence || LEGAL_BASIS }
          end)
        end
        { version:, imported: rows.size }
      end

      def flag(record, coluna) = fetch(record, coluna) == "1"

      def decimal(value)
        texto = value.to_s.tr(",", ".").strip
        return nil if texto.empty?
        format("%.2f", texto.to_d)
      end

      def source_path
        @path ||= begin
          manifest = JSON.parse(File.read(Rails.root.join("db/data/sefaz/manifest.json")))["documentos"]
          melhor = manifest.values.select do |d|
            d["secao"] == "tabelas_apoio" && d["arquivo"].to_s.match?(/\AcClassTrib.*\.xlsx\z/i)
          end.max_by { |d| [d["publicado_em"].to_s, d["arquivo"]] }
          melhor && Rails.root.join("storage/sefaz/tabelas_apoio", melhor["arquivo"]).to_s
        end
        raise ArgumentError, "planilha de cClassTrib não encontrada no espelho" unless @path && File.exist?(@path)
        @path
      end
    end
  end
end
