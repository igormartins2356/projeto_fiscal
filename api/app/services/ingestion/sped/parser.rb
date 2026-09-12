module Ingestion
  module Sped
    # Parser genérico da EFD ICMS/IPI: o leiaute vem da tabela `sped_layout` (registros do cross-check);
    # registros fora da spec são armazenados com campos posicionais (F01, F02…) e não travam o parse.
    class Parser
      class InvalidFile < StandardError; end
      INSERT_BATCH = 2_000

      def self.call(content, client:, storage_ref:, uploaded_by: nil) = new(content, client, storage_ref, uploaded_by).call

      def initialize(content, client, storage_ref, uploaded_by)
        @raw = normalize_encoding(content)
        @client = client
        @storage_ref = storage_ref
        @uploaded_by = uploaded_by
      end

      def call
        lines = @raw.split(/\r?\n/).reject(&:blank?)
        raise InvalidFile, "arquivo não parece uma EFD (primeira linha não é |0000|...)" unless lines.first&.start_with?("|0000|")
        header = split(lines.first)
        layout_date = parse_date(header_field(header, "DT_INI")) or raise InvalidFile, "registro 0000 sem DT_INI válido: não dá para escolher o leiaute vigente"
        @catalog = Catalog::Lookup.new(date: layout_date)
        raise InvalidFile, "tabela sped_layout sem versão publicada" unless @catalog.table_available?("sped_layout")

        hash = Digest::SHA256.hexdigest(@raw)
        existing = Ingestion::FiscalFile.find_by(client_id: @client.id, file_hash: hash)
        return existing if existing&.state == "done"
        file = existing || create_file(header, hash)
        file.records.delete_all if existing   # reprocessamento de um arquivo que ficou em parsing/failed
        file.update!(state: "parsing", errors_log: [], summary: {})
        parse_into(file, lines, header)
      rescue InvalidFile
        raise
      rescue StandardError => e
        # sem isto o arquivo fica preso em "parsing" e o Sidekiq retenta 25× a mesma falha
        Rails.logger.error("Sped::Parser #{@storage_ref}: #{e.class}: #{e.message}")
        file&.update_columns(state: "failed", errors_log: [{ "line" => 0, "error" => "#{e.class}: #{e.message}" }])
        file || raise
      end

      private

      def create_file(header, hash)
        Ingestion::FiscalFile.create!(
          firm_id: @client.firm_id, client: @client, kind: "sped_icms_ipi", storage_ref: @storage_ref, uploaded_by: @uploaded_by,
          layout_version: header_field(header, "COD_VER"), purpose: header_field(header, "COD_FIN") == "1" ? "rectifying" : "original",
          period_start: parse_date(header_field(header, "DT_INI")), period_end: parse_date(header_field(header, "DT_FIN")),
          file_hash: hash, state: "parsing"
        )
      rescue ActiveRecord::RecordNotUnique   # corrida entre dois uploads do mesmo arquivo
        Ingestion::FiscalFile.find_by!(client_id: @client.id, file_hash: hash)
      end

      def parse_into(file, lines, header)
        errors = []
        errors << { line: 1, error: "CNPJ do arquivo (#{header_field(header, 'CNPJ')}) difere do cliente (#{@client.cnpj})" } if header_field(header, "CNPJ").present? && header_field(header, "CNPJ") != @client.cnpj

        rows = []
        counts = Hash.new(0)
        lines.each_with_index do |line, i|
          parts = split(line)
          rec = parts[0].to_s
          next if rec.blank?
          counts[rec] += 1
          spec = @catalog.lookup("sped_layout", [rec])
          names = spec&.dig("fields") || parts[1..].each_index.map { |x| "F#{format('%02d', x + 1)}" }
          fields = {}
          parts[1..].each_with_index { |v, x| fields[names[x] || "F#{format('%02d', x + 1)}"] = normalize_value(v) }
          missing = names.size - (parts.size - 1)
          errors << { line: i + 1, record: rec, error: "#{missing} campo(s) a menos que o leiaute" } if spec && missing > 0 && rec != "9999"
          rows << { record_type: rec, block: rec[0], line_number: i + 1, fields:, level: spec&.dig("level"),
                    document_access_key: (fields[spec["doc_key_field"]].presence if spec&.dig("identifies_document") && spec["doc_key_field"]) }
        end

        persist(file, rows)
        linked = link_documents(file)
        file.update!(state: "done", records_count: rows.size, errors_log: errors.first(200),
                     summary: { "records" => counts, "c100" => counts["C100"], "linked_documents" => linked })
        file
      end

      def split(line) = line.strip.sub(/\A\|/, "").sub(/\|\z/, "").split("|", -1)

      def header_field(parts, name)
        idx = %w[COD_VER COD_FIN DT_INI DT_FIN NOME CNPJ CPF UF IE COD_MUN IM SUFRAMA IND_PERFIL IND_ATIV].index(name)
        parts[idx + 1]&.strip.presence
      end

      def parse_date(v) = v.present? && v.match?(/\A\d{8}\z/) ? Date.strptime(v, "%d%m%Y") : nil

      def normalize_value(v)
        v = v.to_s.strip
        return v unless v.match?(/\A-?\d{1,3}(\.\d{3})*,\d+\z|\A-?\d+,\d+\z/)
        v.delete(".").tr(",", ".")   # decimal brasileiro → canônico
      end

      def normalize_encoding(content)
        c = content.dup.force_encoding("UTF-8")
        return c if c.valid_encoding?
        content.dup.force_encoding("ISO-8859-1").encode("UTF-8")
      end

      # Hierarquia oficial por nível (Guia Prático): o pai é o último registro de nível imediatamente inferior.
      # Uma EFD real tem 10^5–10^6 linhas: grava em blocos e resolve o parent_id num segundo passo por line_number.
      def persist(file, rows)
        stack = {}
        parent_line = {}
        rows.each do |r|
          level = r[:level] || 1
          parent_line[r[:line_number]] = stack[level - 1] if level > 1 && stack[level - 1]
          stack[level] = r[:line_number]
          stack.keys.select { |l| l > level }.each { |l| stack.delete(l) }
        end
        rows.each_slice(INSERT_BATCH) do |slice|
          Ingestion::FiscalRecord.insert_all!(slice.map do |r|
            { fiscal_file_id: file.id, record_type: r[:record_type], block: r[:block], line_number: r[:line_number],
              fields: r[:fields], document_access_key: r[:document_access_key], item_number: r[:fields]["NUM_ITEM"]&.to_i }
          end)
        end
        link_parents(file, parent_line)
      end

      def link_parents(file, parent_line)
        ids = Ingestion::FiscalRecord.where(fiscal_file_id: file.id).pluck(:line_number, :id).to_h
        pairs = parent_line.filter_map { |line, parent| [ids[line], ids[parent]] if ids[line] && ids[parent] }
        pairs.each_slice(INSERT_BATCH) do |slice|
          values = slice.map { |id, parent_id| "(#{id.to_i}, #{parent_id.to_i})" }.join(", ")
          Ingestion::FiscalRecord.connection.update(<<~SQL.squish)
            UPDATE fiscal_records SET parent_id = v.parent_id
            FROM (VALUES #{values}) AS v(id, parent_id) WHERE fiscal_records.id = v.id
          SQL
        end
      end

      # Vínculo registro → documento em um único UPDATE (a EFD traz um C100 por nota)
      def link_documents(file)
        Ingestion::FiscalRecord.connection.update(<<~SQL.squish)
          UPDATE fiscal_records SET document_id = d.id FROM documents d
          WHERE fiscal_records.fiscal_file_id = #{file.id.to_i} AND fiscal_records.document_access_key IS NOT NULL
            AND d.client_id = #{@client.id.to_i} AND d.kind IN ('nfe', 'nfce') AND d.access_key = fiscal_records.document_access_key
        SQL
        Ingestion::FiscalRecord.where(fiscal_file_id: file.id).where.not(document_id: nil).distinct.count(:document_id)
      end
    end
  end
end
