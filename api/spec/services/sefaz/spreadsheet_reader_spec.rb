require "rails_helper"

# As tabelas de apoio da SEFAZ vêm como planilha, e a vigência delas é o dado mais sensível do
# catálogo. Este spec monta planilhas mínimas em memória, sem fixture binária no repositório.
RSpec.describe Sefaz::SpreadsheetReader do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  # Escreve um xlsx mínimo: workbook, sharedStrings e uma planilha.
  def xlsx(nome, linhas, sheet_name: "Plan1")
    textos = linhas.flatten.compact.uniq
    caminho = dir.join(nome)
    Zip::File.open(caminho, create: true) do |z|
      z.get_output_stream("xl/workbook.xml") do |f|
        f.write %(<workbook><sheets><sheet name="#{sheet_name}" sheetId="1"/></sheets></workbook>)
      end
      z.get_output_stream("xl/sharedStrings.xml") do |f|
        f.write "<sst>#{textos.map { |t| "<si><t>#{t}</t></si>" }.join}</sst>"
      end
      z.get_output_stream("xl/worksheets/sheet1.xml") do |f|
        rows = linhas.each_with_index.map do |linha, r|
          celulas = linha.each_with_index.map do |valor, c|
            ref = "#{('A'.ord + c).chr}#{r + 1}"
            # Célula vazia vai como elemento presente e sem valor, que é como a SEFAZ publica.
            next %(<c r="#{ref}"/>) if valor.nil?
            %(<c r="#{ref}" t="s"><v>#{textos.index(valor)}</v></c>)
          end
          %(<row r="#{r + 1}">#{celulas.join}</row>)
        end
        f.write "<worksheet><sheetData>#{rows.join}</sheetData></worksheet>"
      end
    end
    caminho
  end

  def ods(nome, linhas)
    caminho = dir.join(nome)
    Zip::File.open(caminho, create: true) do |z|
      z.get_output_stream("mimetype") { |f| f.write "application/vnd.oasis.opendocument.spreadsheet" }
      z.get_output_stream("content.xml") do |f|
        rows = linhas.map do |linha|
          celulas = linha.map { |v| "<table:table-cell><text:p>#{v}</text:p></table:table-cell>" }
          "<table:table-row>#{celulas.join}</table:table-row>"
        end
        f.write %(<office:document-content xmlns:office="o" xmlns:table="t" xmlns:text="x">) +
                %(<office:body><office:spreadsheet><table:table table:name="Tab">#{rows.join}) +
                "</table:table></office:spreadsheet></office:body></office:document-content>"
      end
    end
    caminho
  end

  it "lê um xlsx preservando cabeçalho, ordem e nome da aba" do
    caminho = xlsx("t.xlsx", [%w[CFOP indDevol], %w[1202 1], %w[5102 0]], sheet_name: "CFOP")
    abas = described_class.call(caminho)
    expect(abas.size).to eq(1)
    expect(abas.first.name).to eq("CFOP")
    expect(abas.first.rows).to eq([%w[CFOP indDevol], %w[1202 1], %w[5102 0]])
    expect(abas.first.records).to eq([{ "CFOP" => "1202", "indDevol" => "1" },
                                      { "CFOP" => "5102", "indDevol" => "0" }])
  end

  it "mantém a posição da coluna quando a célula do meio está vazia" do
    # Sem isso o valor da terceira coluna escorrega para a segunda e a tabela sai torta.
    caminho = xlsx("v.xlsx", [%w[a b c], ["1", nil, "3"]])
    expect(described_class.call(caminho).first.rows.last).to eq(["1", "", "3"])
  end

  it "apara as colunas vazias à direita, que a SEFAZ publica por centenas" do
    caminho = xlsx("w.xlsx", [["CFOP", "indDevol", nil, nil, nil]])
    expect(described_class.call(caminho).first.rows.first).to eq(%w[CFOP indDevol])
  end

  it "lê um ods" do
    caminho = ods("p.ods", [%w[Codigo Pais], %w[1058 Brasil]])
    expect(described_class.call(caminho).first.records).to eq([{ "Codigo" => "1058", "Pais" => "Brasil" }])
  end

  it "detecta o formato pelo conteúdo, não pela extensão" do
    # O portal publicou a tabela de FCP por UF de 2024 com o nome terminando em ".xslsx".
    caminho = xlsx("Tabela_FCP.xslsx", [%w[UF Aliq_1], ["AL", "Fixo:1.00"]])
    expect(described_class.call(caminho).first.records.first).to eq({ "UF" => "AL", "Aliq_1" => "Fixo:1.00" })
  end

  it "recusa planilha binária antiga com mensagem que diz o que fazer" do
    caminho = dir.join("antiga.xls")
    File.binwrite(caminho, "\xD0\xCF\x11\xE0\xA1\xB1\x1A\xE1binario")
    expect { described_class.call(caminho) }
      .to raise_error(described_class::UnsupportedFormat, /binária antiga.*Converta para \.xlsx/m)
  end

  describe ".to_date" do
    it "converte o número serial do Excel" do
      # 38718 é 2006-01-01: é assim que a tabela de CFOP publica o início de vigência.
      expect(described_class.to_date("38718")).to eq(Date.new(2006, 1, 1))
      expect(described_class.to_date("45292")).to eq(Date.new(2024, 1, 1))
    end

    it "aceita data já escrita como texto e devolve nil para vazio ou lixo" do
      expect(described_class.to_date("2026-04-01")).to eq(Date.new(2026, 4, 1))
      expect(described_class.to_date("")).to be_nil
      expect(described_class.to_date("sem data")).to be_nil
    end
  end
end
