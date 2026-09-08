module Ingestion
  module Sped
    # Parser genérico da EFD ICMS/IPI: o leiaute vem da tabela `sped_layout` (registros do cross-check);
    # registros fora da spec são armazenados com campos posicionais (F01, F02…) e não travam o parse.
    class Parser
      class InvalidFile < StandardError; end

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
        layout_date = parse_date(header_field(header, "DT_INI")) || Date.current
        @catalog = Catalog::Lookup.new(date: layout_date)
        raise InvalidFile, "tabela sped_layout sem versão publicada" unless @catalog.table_available?("sped_layout")

        file = Ingestion::FiscalFile.create!(
          firm_id: @client.firm_id, client: @client, kind: "sped_icms_ipi", storage_ref: @storage_ref, uploaded_by: @uploaded_by,
          layout_version: header_field(header, "COD_VER"), purpose: header_field(header, "COD_FIN") == "1" ? "rectifying" : "original",
          period_start: parse_date(header_field(header, "DT_INI")), period_end: parse_date(header_field(header, "DT_FIN")),
          file_hash: Digest::SHA256.hexdigest(@raw), state: "parsing"
        )
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
        docs = Ingestion::Document.where(client_id: @client.id, kind: %w[nfe nfce]).where(access_key: rows.filter_map { |r| r[:document_access_key] }).pluck(:access_key, :id).to_h
        Ingestion::FiscalRecord.where(fiscal_file_id: file.id).where.not(document_access_key: nil).find_each do |r|
          r.update_columns(document_id: docs[r.document_access_key]) if docs[r.document_access_key]
        end
        file.update!(state: "done", records_count: rows.size, errors_log: errors.first(200),
                     summary: { "records" => counts, "c100" => counts["C100"], "linked_documents" => docs.size })
        file
      end

      private

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
      def persist(file, rows)
        stack = {}
        rows.each do |r|
          level = r[:level] || 1
          parent_id = level > 1 ? stack[level - 1] : nil
          rec = Ingestion::FiscalRecord.new(fiscal_file_id: file.id, record_type: r[:record_type], block: r[:block], line_number: r[:line_number],
                                            fields: r[:fields], parent_id:, document_access_key: r[:document_access_key],
                                            item_number: r[:fields]["NUM_ITEM"]&.to_i)
          rec.save!(validate: false)
          stack[level] = rec.id
          stack.keys.select { |l| l > level }.each { |l| stack.delete(l) }
        end
      end
    end
  end
end
