require "csv"

module Catalog
  module Importers
    # Importa linhas para uma versão draft. Aceita CSV (cabeçalho: key_names + colunas de dados + opcionais legal_basis/effective_from/effective_until)
    # ou JSON (array de {key: [], data: {}, ...}). mode replace apaga as linhas atuais; merge faz upsert por chave.
    class Generic
      META = %w[legal_basis effective_from effective_until].freeze

      def initialize(table, version)
        @table = table
        @version = version
      end

      def call(file: nil, rows: nil, mode: "replace", legal_basis: nil)
        parsed = rows.present? ? parse_json(rows) : parse_file(file)
        parsed.each { |r| r[:legal_basis] ||= legal_basis }
        bad = parsed.select { |r| r[:key].size != @table.key_arity || r[:key].any?(&:blank?) }
        raise ArgumentError, "#{bad.size} linha(s) com chave inválida (esperado #{@table.key_arity} parte(s)); ex.: #{bad.first&.dig(:key).inspect}" if bad.any?

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
        raise ArgumentError, "arquivo obrigatório" unless file
        content = file.read.force_encoding("UTF-8")
        content = content.sub(/\A\xEF\xBB\xBF/, "")
        return parse_json(JSON.parse(content)) if file.original_filename.to_s.end_with?(".json") || content.lstrip.start_with?("[")
        sep = content.lines.first.to_s.count(";") > content.lines.first.to_s.count(",") ? ";" : ","
        csv = CSV.parse(content, headers: true, col_sep: sep)
        keys = @table.key_names.map(&:to_s)
        missing = keys - csv.headers.map(&:to_s)
        raise ArgumentError, "CSV sem coluna(s) de chave: #{missing.join(', ')}" if missing.any?
        csv.map do |row|
          h = row.to_h
          { key: keys.map { |k| h[k].to_s.strip }, data: h.except(*keys, *META).transform_values { |v| v&.strip },
            legal_basis: h["legal_basis"], effective_from: h["effective_from"].presence, effective_until: h["effective_until"].presence }
        end
      end
    end
  end
end
