require "zip"
require "nokogiri"

module Sefaz
  # Lê as tabelas de apoio do portal da NF-e, que são publicadas como planilha.
  #
  # Não usa gem de planilha: `xlsx` e `ods` são pacotes ZIP com XML dentro, e o projeto já tem
  # `rubyzip` e `nokogiri`. Ficam fora os 7 arquivos em `xls` binário antigo, que são 6 versões
  # históricas da tabela de NCM (as recentes são `xlsx`) e a tabela de unidades de medida de 2016.
  #
  # Devolve linhas como arrays de strings, preservando a posição da coluna — célula vazia vira "",
  # nunca é omitida, senão o índice das colunas seguintes escorrega e a tabela inteira sai torta.
  class SpreadsheetReader
    class UnsupportedFormat < StandardError; end

    Sheet = Struct.new(:name, :rows, keyword_init: true) do
      # Primeira linha como cabeçalho; cada linha seguinte vira Hash coluna => valor.
      def records
        return [] if rows.empty?
        header = rows.first.map(&:strip)
        rows.drop(1).reject { |r| r.all?(&:empty?) }.map { |r| header.each_with_index.to_h { |h, i| [h, r[i].to_s] } }
      end
    end

    # As planilhas da SEFAZ guardam data como número serial do Excel (38718 é 2006-01-01). Ler como
    # texto e gravar assim produziria vigência errada, que é o dado mais sensível destas tabelas.
    EXCEL_EPOCH = Date.new(1899, 12, 30).freeze

    def self.to_date(value)
      texto = value.to_s.strip
      return nil if texto.empty?
      return EXCEL_EPOCH + texto.to_i if texto.match?(/\A\d{1,6}\z/)
      Date.parse(texto)
    rescue Date::Error
      nil
    end

    def self.call(path) = new(path).call

    def initialize(path)
      @path = path.to_s
    end

    def call
      case format
      when :xlsx then read_xlsx
      when :ods then read_ods
      else
        raise UnsupportedFormat,
              "formato não suportado em #{File.basename(@path)}: planilha binária antiga (.xls) ou " \
              "arquivo que não é planilha. Converta para .xlsx antes de importar."
      end
    end

    private

    # Detecta pelo conteúdo, não pela extensão: o portal publicou a tabela de FCP por UF de 2024 com o
    # nome terminando em ".xslsx" (typo na origem), e o arquivo é xlsx normal.
    def format
      assinatura = File.binread(@path, 8).to_s
      return :desconhecido unless assinatura.start_with?("PK\x03\x04")

      Zip::File.open(@path) do |zip|
        next :xlsx if zip.find_entry("xl/workbook.xml")
        next :ods if zip.find_entry("content.xml") && mimetype(zip).include?("opendocument.spreadsheet")
        :desconhecido
      end
    rescue Zip::Error
      :desconhecido
    end

    def mimetype(zip)
      zip.find_entry("mimetype")&.get_input_stream&.read.to_s
    end

    def read_xlsx
      Zip::File.open(@path) do |zip|
        shared = shared_strings(zip)
        sheet_names = workbook_sheets(zip)
        entries = zip.glob("xl/worksheets/sheet*.xml").sort_by { |e| e.name[/(\d+)\.xml\z/, 1].to_i }
        entries.each_with_index.map do |entry, i|
          Sheet.new(name: sheet_names[i] || "sheet#{i + 1}", rows: xlsx_rows(entry.get_input_stream.read, shared))
        end
      end
    end

    # sharedStrings guarda o texto das células uma vez; a célula referencia pelo índice.
    def shared_strings(zip)
      entry = zip.find_entry("xl/sharedStrings.xml") or return []
      doc = Nokogiri::XML(entry.get_input_stream.read)
      doc.remove_namespaces!
      doc.xpath("//si").map { |si| si.xpath(".//t").map(&:text).join }
    end

    def workbook_sheets(zip)
      entry = zip.find_entry("xl/workbook.xml") or return []
      doc = Nokogiri::XML(entry.get_input_stream.read)
      doc.remove_namespaces!
      doc.xpath("//sheets/sheet").map { |s| s["name"] }
    end

    def xlsx_rows(xml, shared)
      doc = Nokogiri::XML(xml)
      doc.remove_namespaces!
      doc.xpath("//row").map do |row|
        cells = {}
        row.xpath("./c").each do |c|
          index = column_index(c["r"])
          cells[index] = xlsx_value(c, shared)
        end
        next [] if cells.empty?
        linha = (0..cells.keys.max).map { |i| cells[i].to_s }
        # A planilha da SEFAZ vem com centenas de colunas vazias à direita; mantê-las inutiliza o
        # cabeçalho e polui qualquer inspeção.
        linha.pop while linha.last == ""
        linha
      end
    end

    def xlsx_value(cell, shared)
      case cell["t"]
      when "s" then shared[cell.at_xpath("./v")&.text.to_i].to_s
      when "inlineStr" then cell.xpath(".//t").map(&:text).join
      when "str" then cell.at_xpath("./f") ? cell.at_xpath("./v")&.text.to_s : cell.at_xpath("./v")&.text.to_s
      else cell.at_xpath("./v")&.text.to_s
      end
    end

    # "AB12" → 27 (índice zero-based da coluna AB)
    def column_index(ref)
      letters = ref.to_s[/\A[A-Z]+/i].to_s.upcase
      letters.each_char.reduce(0) { |acc, ch| acc * 26 + (ch.ord - 64) } - 1
    end

    def read_ods
      Zip::File.open(@path) do |zip|
        entry = zip.find_entry("content.xml") or raise UnsupportedFormat, "ods sem content.xml"
        doc = Nokogiri::XML(entry.get_input_stream.read)
        doc.remove_namespaces!
        doc.xpath("//table").map do |table|
          Sheet.new(name: table["name"], rows: ods_rows(table))
        end
      end
    end

    def ods_rows(table)
      table.xpath("./table-row").flat_map do |row|
        cells = row.xpath("./table-cell").flat_map do |cell|
          texto = cell.xpath(".//p").map(&:text).join("\n")
          # O ODS comprime célula e linha repetidas num atributo de contagem.
          [texto] * [cell["number-columns-repeated"].to_i, 1].max
        end
        cells = [] if cells.all?(&:empty?)
        cells.pop while cells.last == ""
        [cells] * [row["number-rows-repeated"].to_i, 1].max
      end
    end
  end
end
