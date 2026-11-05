require "rails_helper"

# A tabela oficial traz os códigos e os indicadores; a classificação fiscal (st_role, own_production)
# é curadoria nossa e não pode ser perdida nem inventada na importação.
RSpec.describe Catalog::Importers::Cfop do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  let(:table) do
    Catalog::ReferenceTable.create!(code: "cfop_test", name: "CFOP", key_arity: 1, key_names: %w[cfop])
  end

  # Versão publicada com a curadoria que já existe hoje.
  let!(:publicada) do
    v = table.versions.create!(version: 1, effective_from: Date.new(2003, 1, 1), state: "published",
                               published_at: Time.current)
    Catalog::ReferenceRow.insert_all!([
      { reference_version_id: v.id, key: %w[5102], data: { "nature" => "sale", "st_role" => "none" },
        legal_basis: "Ajuste SINIEF" },
      { reference_version_id: v.id, key: %w[5402], data: { "nature" => "sale", "st_role" => "st_other" },
        legal_basis: "Ajuste SINIEF" }
    ])
    v
  end

  def planilha(linhas)
    caminho = dir.join("Tabela_CFOP.xlsx")
    textos = linhas.flatten.compact.uniq
    Zip::File.open(caminho, create: true) do |z|
      z.get_output_stream("xl/workbook.xml") { |f| f.write %(<workbook><sheets><sheet name="CFOP" sheetId="1"/></sheets></workbook>) }
      z.get_output_stream("xl/sharedStrings.xml") { |f| f.write "<sst>#{textos.map { |t| "<si><t>#{t}</t></si>" }.join}</sst>" }
      z.get_output_stream("xl/worksheets/sheet1.xml") do |f|
        rows = linhas.each_with_index.map do |linha, r|
          cels = linha.each_with_index.map do |v, c|
            ref = "#{('A'.ord + c).chr}#{r + 1}"
            v.nil? ? %(<c r="#{ref}"/>) : %(<c r="#{ref}" t="s"><v>#{textos.index(v)}</v></c>)
          end
          %(<row r="#{r + 1}">#{cels.join}</row>)
        end
        f.write "<worksheet><sheetData>#{rows.join}</sheetData></worksheet>"
      end
    end
    caminho
  end

  let(:cabecalho) do
    ["CFOP", "Início de vigência", "Fim de vigência", "indNFe", "indComunica", "indTransp",
     "indDevol", "indRetor", "indAnula", "indRemes", "indComb", "indExcIBSCBS",
     "Título do CFOP", "Descrição (nota explicativa)"]
  end

  def linha(cfop, ini: "38718", devol: "0", anula: "0", titulo: nil)
    [cfop, ini, nil, "1", "0", "0", devol, "0", anula, "0", "0", "0", titulo, nil]
  end

  subject(:importer) { described_class.new(table, path: planilha(linhas).to_s) }

  let(:linhas) do
    [cabecalho,
     linha("5102", titulo: "Venda de mercadoria adquirida de terceiros"),
     linha("5402", titulo: "Venda entre substitutos do mesmo produto"),
     linha("1202", devol: "1", titulo: "Devolução de venda"),
     linha("1205", anula: "1", titulo: "Anulação de valor de serviço de comunicação")]
  end

  it "importa os códigos oficiais com indicadores, título e vigência de cada linha" do
    resultado = importer.call
    version = resultado[:version]

    expect(version.state).to eq("draft")
    expect(resultado[:imported]).to eq(4)
    linha_1202 = version.rows.find_by(key: %w[1202])
    expect(linha_1202.data).to include("ind_devol" => true, "ind_anula" => false, "direction" => "inbound",
                                       "title" => "Devolução de venda")
    expect(linha_1202.effective_from).to eq(Date.new(2006, 1, 1))
    expect(linha_1202.legal_basis).to include("Ajuste SINIEF")
    # A oficial marca anulação de valor, que é o que distingue 1205 de uma devolução.
    expect(version.rows.find_by(key: %w[1205]).data).to include("ind_anula" => true, "ind_devol" => false)
  end

  it "preserva a classificação curada de quem já tinha, e deixa ausente para o código novo" do
    version = importer.call[:version]

    expect(version.rows.find_by(key: %w[5402]).data).to include("st_role" => "st_other", "nature" => "sale")
    # 1202 e 1205 não existiam na versão publicada: sem palpite, o campo fica ausente.
    nova = version.rows.find_by(key: %w[1202]).data
    expect(nova).not_to have_key("st_role")
    expect(nova).not_to have_key("own_production")
    expect(importer.call[:without_curation]).to eq(2)
  end

  it "não começa depois da versão publicada, para não deixar período sem tabela" do
    # A menor vigência das linhas é 2006, mas a publicada cobre desde 2003.
    expect(importer.call[:version].effective_from).to eq(Date.new(2003, 1, 1))
  end

  it "ignora linha que não é código de CFOP (rodapé e nota da planilha)" do
    lixo = [cabecalho, linha("5102"), ["Fonte: Ajuste SINIEF", nil, nil], ["", nil, nil]]
    imp = described_class.new(table, path: planilha(lixo).to_s)
    expect(imp.call[:imported]).to eq(1)
  end

  it "recusa planilha sem nenhum código" do
    imp = described_class.new(table, path: planilha([cabecalho]).to_s)
    expect { imp.call }.to raise_error(ArgumentError, /sem linhas de CFOP/)
  end
end
