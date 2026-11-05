require "rails_helper"

# A planilha distingue alíquota fixa de teto ("Fixo:2.00" × "Max:4.00"), e a UF pode admitir mais de
# uma. Tratar tudo como um valor único produziria apontamento errado.
RSpec.describe Catalog::Importers::FcpUf do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  let(:table) do
    Catalog::ReferenceTable.create!(code: "fcp_uf_test", name: "FCP", key_arity: 1, key_names: %w[uf])
  end

  def planilha(linhas)
    caminho = dir.join("Tabela_Aliquotas_FCP_por_UF.xlsx")
    textos = linhas.flatten.compact.uniq
    Zip::File.open(caminho, create: true) do |z|
      z.get_output_stream("xl/workbook.xml") { |f| f.write %(<workbook><sheets><sheet name="FCP" sheetId="1"/></sheets></workbook>) }
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

  let(:cabecalho) { ["cUF", "UF", "Nome UF", "Aliq_1", "Aliq_2", "Aliq_3", ".", "Observação"] }
  let(:linhas) do
    [cabecalho,
     ["12", "AC", "ACRE", "Fixo:0.00", nil, nil, nil, "UF não possui FCP"],
     ["27", "AL", "ALAGOAS", "Fixo:1.00", "Fixo:2.00", nil, nil, "UF com até 3 Alíquotas possíveis"],
     ["33", "RJ", "RIO DE JANEIRO", "Max:4.00", nil, nil, nil, "UF com alíquota máxima de 4.00"],
     ["35", "SP", "SAO PAULO", "Fixo: 2.00", nil, nil, nil, "Alíquota única de 2.00"],
     [nil, nil, "Fonte: Portal da NF-e", nil, nil, nil, nil, nil]]
  end

  subject(:importer) { described_class.new(table, path: planilha(linhas).to_s) }

  it "importa as UFs com a lista de alíquotas admitidas" do
    resultado = importer.call
    expect(resultado[:imported]).to eq(4)
    expect(resultado[:with_fcp]).to eq(3)
    expect(resultado[:version].state).to eq("draft")
    expect(resultado[:version].rows.find_by(key: %w[AL]).data)
      .to include("has_fcp" => true, "rates" => %w[1.00 2.00], "max_rate" => "2.00", "kinds" => %w[fixed])
  end

  it "distingue teto de alíquota fixa" do
    version = importer.call[:version]
    expect(version.rows.find_by(key: %w[RJ]).data).to include("kinds" => %w[max], "rates" => %w[4.00])
    expect(version.rows.find_by(key: %w[SP]).data).to include("kinds" => %w[fixed])
  end

  it "marca como sem FCP a UF cuja única alíquota é zero" do
    expect(importer.call[:version].rows.find_by(key: %w[AC]).data)
      .to include("has_fcp" => false, "note" => "UF não possui FCP")
  end

  it "tolera espaço depois do tipo e ignora o rodapé da planilha" do
    version = importer.call[:version]
    expect(version.rows.find_by(key: %w[SP]).data["rates"]).to eq(%w[2.00])
    expect(version.rows.count).to eq(4)
  end

  it "recusa planilha sem nenhuma UF" do
    imp = described_class.new(table, path: planilha([cabecalho]).to_s)
    expect { imp.call }.to raise_error(ArgumentError, /sem linhas de UF/)
  end
end
