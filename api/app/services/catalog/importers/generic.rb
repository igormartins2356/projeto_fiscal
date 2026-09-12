require "csv"

module Catalog
  module Importers
    # Importa linhas para uma versão draft. Aceita CSV (cabeçalho: key_names + colunas de dados + opcionais legal_basis/effective_from/effective_until)
    # ou JSON (array de {key: [], data: {}, ...}). mode replace apaga as linhas atuais; merge faz upsert por chave.
    class Generic
      # Erro de dado do arquivo importado (vira 422 no painel) — distinto de ArgumentError de programação.
      class InvalidData < ArgumentError; end

      META = %w[legal_basis effective_from effective_until].freeze
      # Decimal exportado de planilha brasileira ("18,00", "1.234,56"): gravado assim, viraria BigDecimal("18") nas regras.
      BR_DECIMAL = /\A-?(\d{1,3}(\.\d{3})+|\d+),\d+\z/

      def initialize(table, version)
        @table = table
        @version = version
      end

      def call(file: nil, rows: nil, mode: "replace", legal_basis: nil)
        raise InvalidData, "versão v#{@version.version} está #{@version.state}: só versão draft recebe linhas (crie uma nova versão)" unless @version.state == "draft"
        parsed = rows.present? ? parse_json(rows) : parse_file(file)
        parsed.each { |r| r[:legal_basis] ||= legal_basis }
        bad = parsed.select { |r| r[:key].size != @table.key_arity || r[:key].any?(&:blank?) }
        raise InvalidData, "#{bad.size} linha(s) com chave inválida (esperado #{@table.key_arity} parte(s)); ex.: #{bad.first&.dig(:key).inspect}" if bad.any?
        repeated = parsed.group_by { |r| r[:key] }.select { |_, rs| rs.size > 1 }.keys
        raise InvalidData, "#{repeated.size} chave(s) repetida(s) no arquivo (a última venceria em silêncio); ex.: #{repeated.first.inspect}" if repeated.any?
        apply_row_schema!(parsed)

        Catalog::ReferenceRow.transaction do
          if mode == "replace"
            @version.rows.delete_all
          else
            parsed.each { |r| @version.rows.where("key = ARRAY[?]::varchar[]", r[:key]).delete_all }
          end
          Catalog::ReferenceRow.insert_all!(parsed.map { |r| r.merge(reference_version_id: @version.id) }) if parsed.any?
        end
        { imported: parsed.size, mode:, rows_count: @version.rows.count }
      end

      private

      def parse_json(rows)
        rows = JSON.parse(rows) if rows.is_a?(String)
        rows.map { |r| r = r.to_h.stringify_keys; { key: Array(r["key"]).map(&:to_s), data: r["data"] || {}, legal_basis: r["legal_basis"], effective_from: r["effective_from"], effective_until: r["effective_until"] } }
      end

      def parse_file(file)
        raise InvalidData, "arquivo obrigatório" unless file
        content = decode(file.read)
        content = content.sub(/\A\xEF\xBB\xBF/, "")
        return parse_json(JSON.parse(content)) if file.original_filename.to_s.end_with?(".json") || content.lstrip.start_with?("[")
        sep = content.lines.first.to_s.count(";") > content.lines.first.to_s.count(",") ? ";" : ","
        csv = CSV.parse(content, headers: true, col_sep: sep)
        keys = @table.key_names.map(&:to_s)
        missing = keys - csv.headers.map(&:to_s)
        raise InvalidData, "CSV sem coluna(s) de chave: #{missing.join(', ')}" if missing.any?
        csv.map do |row|
          h = row.to_h
          { key: keys.map { |k| h[k].to_s.strip }, data: h.except(*keys, *META).transform_values { |v| normalize_decimal(v&.strip) },
            legal_basis: h["legal_basis"], effective_from: h["effective_from"].presence, effective_until: h["effective_until"].presence }
        end
      end

      # Fonte oficial (CONFAZ, SEFAZ, Portal SPED) ainda publica CSV em ISO-8859-1: sem fallback, CSV.parse levanta em "São Paulo".
      def decode(raw)
        utf8 = raw.dup.force_encoding(Encoding::UTF_8)
        return utf8 if utf8.valid_encoding?
        raw.dup.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
      end

      def normalize_decimal(value) = value.is_a?(String) && value.match?(BR_DECIMAL) ? value.delete(".").tr(",", ".") : value

      # row_schema da tabela: { "coluna" => "decimal" } ou { "coluna" => { "type" => "decimal", "required" => true } }.
      # Sem essa checagem, dado fora do tipo só aparece como evaluation_error no meio de um run do contador.
      def apply_row_schema!(parsed)
        schema = @table.row_schema.presence or return
        problems = []
        parsed.each do |r|
          schema.each do |column, spec|
            spec = { "type" => spec } if spec.is_a?(String)
            raw = r[:data][column]
            if raw.nil? || raw.to_s.strip.empty?
              problems << "#{r[:key].join('|')}: coluna '#{column}' é obrigatória" if spec["required"]
              next
            end
            cast = cast_value(raw, spec["type"])
            cast.nil? ? problems << "#{r[:key].join('|')}: '#{raw}' não é #{spec['type']} válido na coluna '#{column}'" : r[:data][column] = cast
          end
        end
        raise InvalidData, "#{problems.size} linha(s) fora do esquema da tabela; ex.: #{problems.first}" if problems.any?
      end

      # Decimal fica string (serialização de decimal é string em todo o canônico); demais tipos viram o valor JSON.
      def cast_value(raw, type)
        value = raw.is_a?(String) ? normalize_decimal(raw.strip) : raw
        case type.to_s
        when "decimal" then BigDecimal(value.to_s) && value.to_s
        when "integer" then Integer(value.to_s, 10)
        when "boolean" then { "true" => true, "false" => false, "1" => true, "0" => false, "sim" => true, "nao" => false, "não" => false }.fetch(value.to_s.downcase)
        when "date" then Date.parse(value.to_s).iso8601
        else value
        end
      rescue ArgumentError, TypeError, KeyError, Date::Error
        nil
      end
    end
  end
end
