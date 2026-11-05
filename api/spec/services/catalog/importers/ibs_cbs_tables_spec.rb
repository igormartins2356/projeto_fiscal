require "rails_helper"

# A planilha oficial acrescenta a vigência de cada classificação, que o catálogo não tinha, e a matriz
# de grupos por CST. O formato que as regras publicadas já consomem precisa sobreviver à importação.
RSpec.describe Catalog::Importers::IbsCbsTables do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  let!(:classes_table) do
    Catalog::ReferenceTable.create!(code: "ibs_cbs_class", name: "cClassTrib", key_arity: 1,
                                    key_names: %w[class_code], source_class: "A")
  end

  def planilha(abas)
    caminho = dir.join("cClassTrib_2026-06-22.xlsx")
    textos = abas.values.flatten(1).flatten.compact.uniq
    Zip::File.open(caminho, create: true) do |z|
      sheets = abas.keys.each_with_index.map { |n, i| %(<sheet name="#{n}" sheetId="#{i + 1}"/>) }
      z.get_output_stream("xl/workbook.xml") { |f| f.write "<workbook><sheets>#{sheets.join}</sheets></workbook>" }
      z.get_output_stream("xl/sharedStrings.xml") { |f| f.write "<sst>#{textos.map { |t| "<si><t>#{t}</t></si>" }.join}</sst>" }
      abas.values.each_with_index do |linhas, i|
        z.get_output_stream("xl/worksheets/sheet#{i + 1}.xml") do |f|
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
    end
    caminho
  end

  # A SEFAZ publicou uma das colunas como "ind_ gCredPresIBSZFM", com espaço no meio.
  let(:aba_cst) do
    [["CST-IBS/CBS", "Descrição CST-IBS/CBS", "ind_gIBSCBS", "ind_gRed", "ind_ gCredPresIBSZFM"],
     %w[000 Tributação\ integral 1 0 0],
     %w[010 Alíquotas\ uniformes 1 0 0],
     ["", "Fonte: portal", nil, nil, nil]]
  end

  let(:aba_class) do
    [["CST-IBS/CBS", "Descrição CST-IBS/CBS", "cClassTrib", "Nome cClassTrib", "Descrição cClassTrib",
      "LC 214/25", "Tipo de Alíquota", "pRedIBS", "pRedCBS", "ind_gTribRegular", "tpRBSN",
      "dIniVig", "dFimVig", "indNFe", "indNFCe", "ANEXO", "Link"],
     ["000", "Tributação integral", "000001", "Integral", "Tributadas integralmente", "art. 4º",
      "Padrão", "0", "0", "0", "1", "46023", nil, "1", "1", nil, "https://exemplo"],
     ["011", "Redução", "011001", "Reduzida 60", "Com redução de 60%", "art. 9º",
      "Reduzida", "60", "60", "0", "1", "46023", "46388", "1", "0", "90111", nil]]
  end

  subject(:importer) do
    described_class.new(path: planilha("cClass 2026" => aba_class, "CST 2026" => aba_cst).to_s)
  end

  it "importa as classificações com a vigência de cada uma, que é o que faltava no catálogo" do
    resultado = importer.call
    version = resultado[:classes][:version]

    expect(resultado[:classes][:imported]).to eq(2)
    linha = version.rows.find_by(key: %w[000001])
    expect(linha.effective_from).to eq(Date.new(2026, 1, 1))
    expect(version.rows.find_by(key: %w[011001]).effective_until).to eq(Date.new(2027, 1, 1))
  end

  it "preserva os campos que as regras publicadas já consomem" do
    linha = importer.call[:classes][:version].rows.find_by(key: %w[011001])
    expect(linha.data).to include(
      "cst" => "011", "cst_name" => "Redução", "short_name" => "Reduzida 60",
      "reduction_ibs_pct" => "60.00", "reduction_cbs_pct" => "60.00", "annex" => "90111"
    )
    expect(linha.data["indicators"]).to include("nfe" => true, "nfce" => false)
    expect(linha.legal_basis).to eq("art. 9º")
  end

  it "acrescenta o que a planilha traz de novo" do
    linha = importer.call[:classes][:version].rows.find_by(key: %w[000001])
    expect(linha.data).to include("rate_type" => "Padrão", "tp_rbsn" => "1", "link" => "https://exemplo")
    expect(linha.data["group_indicators"]).to include("TribRegular" => false)
  end

  it "importa a matriz de grupos por CST, tolerando o espaço no nome da coluna" do
    resultado = importer.call[:csts]
    expect(resultado[:imported]).to eq(2)
    cst = resultado[:version].rows.find_by(key: %w[010])
    expect(cst.data["description"]).to eq("Alíquotas uniformes")
    expect(cst.data["groups"]).to include("ibscbs" => true, "red" => false, "credpresibszfm" => false)
  end

  it "não começa depois da versão publicada" do
    v1 = classes_table.versions.create!(version: 1, effective_from: Date.new(2025, 5, 5),
                                        state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: v1.id, key: %w[000001], data: {},
                                         legal_basis: "LC 214/2025" }])
    expect(importer.call[:classes][:version].effective_from).to eq(Date.new(2025, 5, 5))
  end

  it "recusa planilha sem a aba esperada" do
    imp = described_class.new(path: planilha("Outra" => [%w[A B], %w[1 2]]).to_s)
    expect { imp.call }.to raise_error(ArgumentError, /sem a aba/)
  end
end
