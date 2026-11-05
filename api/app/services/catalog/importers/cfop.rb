module Catalog
  module Importers
    # Importa a tabela oficial de CFOP publicada no Portal da NF-e (seção Diversos, Informe Técnico
    # 2023.002), que é planilha. Fonte espelhada por `Sefaz::DocumentSync` em storage/sefaz.
    #
    # A planilha traz o que nós não tínhamos: os 619 códigos (a nossa tinha 515, um recorte que gerou
    # falso positivo), a vigência de cada um, e os indicadores oficiais de devolução, retorno,
    # anulação, remessa e combustível — que é a marcação que várias regras precisavam e que estava
    # sendo deduzida.
    #
    # O que a planilha NÃO traz é a nossa classificação fiscal (`st_role`, `own_production`,
    # `nature`), que foi curada à mão. Ela é **preservada** da versão vigente, código por código. Para
    # o código novo, que a nossa tabela não tinha, esses campos ficam **ausentes** em vez de receber um
    # palpite: ausência vira erro de avaliação visível, enquanto "none" vira silêncio.
    class Cfop
      SOURCE = "Portal da NF-e — Tabela de CFOP (IT 2023.002), seção Diversos".freeze
      LEGAL_BASIS = "Ajuste SINIEF s/nº de 1970, Anexo — Código Fiscal de Operações e Prestações".freeze

      # Colunas da planilha → chaves da linha. Mantém o nome oficial do indicador, para rastrear.
      INDICATORS = {
        "indNFe" => "ind_nfe", "indComunica" => "ind_comunica", "indTransp" => "ind_transp",
        "indDevol" => "ind_devol", "indRetor" => "ind_retor", "indAnula" => "ind_anula",
        "indRemes" => "ind_remes", "indComb" => "ind_comb", "indExcIBSCBS" => "ind_exc_ibs_cbs"
      }.freeze

      # Campos da nossa curadoria, preservados da versão anterior.
      CURATED = %w[nature st_role st_related own_production requires_reference].freeze

      def initialize(table = nil, path: nil)
        @table = table || Catalog::ReferenceTable.find_by!(code: "cfop")
        @path = path
      end

      def call(user: nil)
        rows = parse
        raise ArgumentError, "planilha sem linhas de CFOP" if rows.empty?

        previous = previous_rows
        version = nil
        Catalog::ReferenceVersion.transaction do
          last = @table.versions.order(version: :desc).first
          version = @table.versions.create!(
            version: (last&.version || 0) + 1, state: "draft", source_url: SOURCE, imported_by: user,
            effective_from: version_start(rows),
            notes: "#{rows.size} CFOPs da planilha oficial (#{File.basename(source_path)}); " \
                   "classificação curada preservada de #{previous.size} códigos"
          )
          Catalog::ReferenceRow.insert_all!(rows.map { |r| build_row(version, r, previous) })
        end
        { version:, imported: rows.size, curated_kept: rows.count { |r| previous.key?(r[:code]) },
          without_curation: rows.count { |r| !previous.key?(r[:code]) } }
      end

      private

      # A versão substitui a anterior e não pode começar depois dela, senão o período que a anterior
      # cobria fica sem tabela. A vigência de cada código continua na linha.
      def version_start(rows)
        menor_linha = rows.filter_map { |r| r[:effective_from] }.min
        anterior = @table.versions.published.minimum(:effective_from)
        [menor_linha, anterior, Date.current].compact.min
      end

      # A versão mais recente sai do manifesto do espelho, pela data de publicação. Adivinhar pelo nome
      # do arquivo escolhe errado: a planilha de setembro de 2026 se chama "IT_2023_002_v2_10...".
      def source_path
        @path ||= begin
          manifest = JSON.parse(File.read(Rails.root.join("db/data/sefaz/manifest.json")))["documentos"]
          candidatos = manifest.values.select do |d|
            d["secao"] == "tabelas_apoio" && d["arquivo"].to_s.match?(/Tabela_CFOP.*\.xlsx\z/i)
          end
          melhor = candidatos.max_by { |d| [d["publicado_em"].to_s, d["arquivo"]] }
          melhor && Rails.root.join("storage/sefaz/tabelas_apoio", melhor["arquivo"]).to_s
        end
        raise ArgumentError, "tabela de CFOP não encontrada no espelho (rode rake sefaz:sync)" unless @path && File.exist?(@path)
        @path
      end

      def parse
        sheet = Sefaz::SpreadsheetReader.call(source_path).max_by { |s| s.rows.size }
        sheet.records.filter_map do |record|
          code = record["CFOP"].to_s.strip
          next unless code.match?(/\A\d{4}\z/)
          {
            code:,
            effective_from: Sefaz::SpreadsheetReader.to_date(record["Início de vigência"]),
            effective_until: Sefaz::SpreadsheetReader.to_date(record["Fim de vigência"]),
            title: presence(record["Título do CFOP"]),
            description: presence(record["Descrição (nota explicativa)"]),
            indicators: INDICATORS.to_h { |coluna, chave| [chave, record[coluna].to_s.strip == "1"] }
          }
        end
      end

      def previous_rows
        version = @table.versions.published.order(:effective_from, :version).last
        return {} unless version
        version.rows.pluck(:key, :data).to_h { |key, data| [Array(key).first.to_s, data] }
      end

      def build_row(version, parsed, previous)
        curated = (previous[parsed[:code]] || {}).slice(*CURATED)
        data = parsed[:indicators].merge(curated)
        data["title"] = parsed[:title] if parsed[:title]
        data["description"] = parsed[:description] if parsed[:description]
        # `direction` sai do próprio código: 1/2/3 é entrada, 5/6/7 é saída. É dedução segura, ao
        # contrário de st_role e own_production, que são curadoria.
        data["direction"] = parsed[:code].start_with?("1", "2", "3") ? "inbound" : "outbound"
        { reference_version_id: version.id, key: [parsed[:code]], data:,
          effective_from: parsed[:effective_from], effective_until: parsed[:effective_until],
          legal_basis: LEGAL_BASIS }
      end

      def presence(value) = value.to_s.strip.presence
    end
  end
end
