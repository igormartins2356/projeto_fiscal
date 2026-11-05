module Catalog
  module Importers
    # Importa a Tabela de Alíquotas de FCP por UF publicada no Portal da NF-e (seção Diversos), que é
    # planilha. Fonte espelhada por `Sefaz::DocumentSync`.
    #
    # É a fonte que faltava: a alíquota interna do catálogo guarda um `fcp_rate` único, mas a UF pode
    # admitir mais de uma alíquota de fundo de combate à pobreza, e em alguns estados o valor é um
    # teto, não um valor fixo. A planilha publica isso explicitamente ("Fixo:2.00", "Max:4.00").
    #
    # `rates` é a lista das alíquotas admitidas, para a regra comparar o que veio no XML com o
    # operador `in`; `max_rate` é o teto. UF sem o adicional fica com `has_fcp` falso e lista vazia.
    class FcpUf
      TABLE_CODE = "fcp_uf".freeze
      SOURCE = "Portal da NF-e — Tabela de Alíquotas de FCP por UF, seção Diversos".freeze
      LEGAL_BASIS = "Convênio ICMS 42/2016 e legislação estadual do fundo de combate à pobreza".freeze
      RATE = /\A\s*(fixo|max)\s*:\s*([\d.,]+)\s*\z/i

      def initialize(table = nil, path: nil)
        @table = table || find_or_create_table
        @path = path
      end

      def call(user: nil)
        rows = parse
        raise ArgumentError, "planilha de FCP sem linhas de UF" if rows.empty?

        version = nil
        Catalog::ReferenceVersion.transaction do
          last = @table.versions.order(version: :desc).first
          version = @table.versions.create!(
            version: (last&.version || 0) + 1, state: "draft", source_url: SOURCE, imported_by: user,
            effective_from: published_on, notes: "#{rows.size} UFs da planilha oficial (#{File.basename(source_path)})"
          )
          Catalog::ReferenceRow.insert_all!(rows.map do |r|
            { reference_version_id: version.id, key: [r[:uf]], data: r[:data], legal_basis: LEGAL_BASIS }
          end)
        end
        { version:, imported: rows.size, with_fcp: rows.count { |r| r[:data]["has_fcp"] } }
      end

      private

      def find_or_create_table
        Catalog::ReferenceTable.find_or_create_by!(code: TABLE_CODE) do |t|
          t.name = "Alíquota do FCP por UF"
          t.key_names = %w[uf]
          t.key_arity = 1
          t.source_class = "A"
          t.source_url = SOURCE
        end
      end

      # A planilha não traz data de vigência; a data de publicação do documento no portal é o que
      # temos, e está no manifesto do espelho.
      def published_on
        Sefaz::SpreadsheetReader.to_date(manifest_entry&.dig("publicado_em")) || Date.current
      end

      def source_path
        @path ||= manifest_entry && Rails.root.join("storage/sefaz/tabelas_apoio", manifest_entry["arquivo"]).to_s
        raise ArgumentError, "tabela de FCP não encontrada no espelho (rode rake sefaz:sync)" unless @path && File.exist?(@path)
        @path
      end

      def manifest_entry
        @manifest_entry ||= begin
          manifest = JSON.parse(File.read(Rails.root.join("db/data/sefaz/manifest.json")))["documentos"]
          manifest.values.select { |d| d["secao"] == "tabelas_apoio" && d["arquivo"].to_s.match?(/FCP_por_UF/i) }
                  .max_by { |d| [d["publicado_em"].to_s, d["arquivo"]] }
        end
      end

      def parse
        sheet = Sefaz::SpreadsheetReader.call(source_path).max_by { |s| s.rows.size }
        sheet.records.filter_map do |record|
          uf = record["UF"].to_s.strip.upcase
          next unless uf.match?(/\A[A-Z]{2}\z/)
          entradas = %w[Aliq_1 Aliq_2 Aliq_3].filter_map { |coluna| parse_rate(record[coluna]) }
          rates = entradas.map { |e| e[:rate] }.uniq
          { uf:, data: {
            "has_fcp" => rates.any? { |r| r.to_d.positive? },
            "rates" => rates,
            "max_rate" => rates.max_by(&:to_d),
            "kinds" => entradas.map { |e| e[:kind] }.uniq,
            "note" => record["Observação"].to_s.strip.presence
          }.compact }
        end
      end

      # "Fixo:2.00" e "Max:4.00" — o segundo é teto, não valor exato, e a regra precisa saber a
      # diferença para não acusar uma alíquota menor que o máximo.
      def parse_rate(value)
        m = RATE.match(value.to_s) or return nil
        { kind: m[1].downcase == "max" ? "max" : "fixed", rate: format("%.2f", m[2].tr(",", ".").to_d) }
      end
    end
  end
end
