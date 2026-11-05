require "rails_helper"

# O esquema é a fonte normativa do leiaute. O que este spec protege: o caminho completo de cada campo
# (o mesmo nome de tag existe em vários grupos), as enumerações (valores válidos) e a escala decimal,
# que a SEFAZ codifica no nome do tipo.
RSpec.describe Sefaz::LayoutExtractor do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  def pacote(leiaute, tipos: nil)
    caminho = dir.join("PL_010f_v1.04.zip")
    Zip::File.open(caminho, create: true) do |z|
      z.get_output_stream("PL/leiauteNFe_v4.00.xsd") { |f| f.write leiaute }
      z.get_output_stream("PL/tiposBasico_v4.00.xsd") { |f| f.write tipos } if tipos
      # A assinatura não é leiaute fiscal e tem de ser ignorada.
      z.get_output_stream("PL/xmldsig-core-schema_v1.01.xsd") { |f| f.write "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"/>" }
    end
    caminho
  end

  let(:tipos) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:simpleType name="TDec_1302">
          <xs:annotation><xs:documentation>13 de corpo e 2 decimais</xs:documentation></xs:annotation>
          <xs:restriction base="xs:string"><xs:pattern value="0|[1-9]{1}[0-9]{0,12}(\\.[0-9]{2})?"/></xs:restriction>
        </xs:simpleType>
        <xs:simpleType name="TSerie">
          <xs:restriction base="xs:string"><xs:minLength value="1"/><xs:maxLength value="3"/></xs:restriction>
        </xs:simpleType>
      </xs:schema>
    XSD
  end

  let(:leiaute) do
    <<~XSD
      <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        <xs:element name="NFe">
          <xs:complexType>
            <xs:sequence>
              <xs:element name="infNFe">
                <xs:complexType>
                  <xs:sequence>
                    <xs:element name="ide">
                      <xs:complexType>
                        <xs:sequence>
                          <xs:element name="serie" type="TSerie">
                            <xs:annotation><xs:documentation>Série do documento</xs:documentation></xs:annotation>
                          </xs:element>
                          <xs:element name="tpNF">
                            <xs:simpleType>
                              <xs:restriction base="xs:string">
                                <xs:enumeration value="0"/>
                                <xs:enumeration value="1"/>
                              </xs:restriction>
                            </xs:simpleType>
                          </xs:element>
                          <xs:element name="dhSaiEnt" type="TSerie" minOccurs="0"/>
                        </xs:sequence>
                      </xs:complexType>
                    </xs:element>
                    <xs:element name="det" maxOccurs="990">
                      <xs:complexType>
                        <xs:sequence>
                          <xs:element name="prod">
                            <xs:complexType>
                              <xs:sequence>
                                <xs:element name="vProd" type="TDec_1302"/>
                              </xs:sequence>
                            </xs:complexType>
                          </xs:element>
                          <xs:element name="imposto">
                            <xs:complexType>
                              <xs:sequence>
                                <xs:choice>
                                  <xs:element name="IPI" minOccurs="0">
                                    <xs:complexType>
                                      <xs:sequence>
                                        <xs:element name="cEnq" type="TSerie"/>
                                      </xs:sequence>
                                    </xs:complexType>
                                  </xs:element>
                                  <xs:element name="ISSQN" minOccurs="0" type="TSerie"/>
                                </xs:choice>
                              </xs:sequence>
                            </xs:complexType>
                          </xs:element>
                        </xs:sequence>
                      </xs:complexType>
                    </xs:element>
                  </xs:sequence>
                </xs:complexType>
              </xs:element>
            </xs:sequence>
          </xs:complexType>
        </xs:element>
      </xs:schema>
    XSD
  end

  subject(:campos) { described_class.call(package_path: pacote(leiaute, tipos: tipos).to_s) }

  it "extrai cada campo com o caminho completo até ele" do
    caminhos = campos.map(&:path)
    expect(caminhos).to include("NFe/infNFe/ide/serie", "NFe/infNFe/det/prod/vProd")
    # A raiz não é campo; o que importa é o caminho, porque o mesmo nome de tag repete em grupos.
    expect(caminhos).not_to include("NFe")
    serie = campos.find { |c| c.path == "NFe/infNFe/ide/serie" }
    expect(serie.parent_path).to eq("NFe/infNFe/ide")
    expect(serie.level).to eq(3)
  end

  it "traz tipo, tamanho e documentação do tipo nomeado" do
    serie = campos.find { |c| c.tag == "serie" }
    expect(serie.type).to eq("TSerie")
    expect(serie.min_length).to eq("1")
    expect(serie.max_length).to eq("3")
    expect(serie.documentation).to eq("Série do documento")
  end

  it "traz as enumerações, que são os valores válidos do campo" do
    expect(campos.find { |c| c.tag == "tpNF" }.enumerations).to eq(%w[0 1])
    expect(campos.find { |c| c.tag == "tpNF" }.to_h["enumerations"]).to eq(%w[0 1])
  end

  it "lê a escala decimal do nome do tipo, que é como a SEFAZ a publica" do
    expect(campos.find { |c| c.tag == "vProd" }.decimals).to eq(2)
  end

  it "distingue campo obrigatório, opcional e repetível" do
    expect(campos.find { |c| c.tag == "serie" }.to_h).to include("required" => true, "repeats" => false)
    expect(campos.find { |c| c.tag == "dhSaiEnt" }.to_h).to include("required" => false)
    expect(campos.find { |c| c.tag == "det" }.to_h).to include("repeats" => true, "max_occurs" => "990")
  end

  it "recusa pacote sem esquema e pacote sem o elemento raiz" do
    vazio = dir.join("PL_vazio.zip")
    Zip::File.open(vazio, create: true) { |z| z.get_output_stream("leia.txt") { |f| f.write "x" } }
    expect { described_class.call(package_path: vazio.to_s) }.to raise_error(ArgumentError, /sem nenhum esquema/)

    outro = pacote('<xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"><xs:element name="CTe"/></xs:schema>')
    expect { described_class.call(package_path: outro.to_s) }.to raise_error(ArgumentError, /NFe não encontrado/)
  end
  # Descer o esquema com "//" a partir de cada grupo visita neto como se fosse filho: o campo cEnq,
  # que vive dentro do IPI, apareceria também como filho direto de imposto, e no esquema real isso
  # produziu 14 caminhos duplicados, que a importação rejeitou no índice único da tabela.
  it "trata choice e sequence como conectores, sem promover neto a filho direto" do
    caminhos = campos.map(&:path)
    expect(caminhos).to include("NFe/infNFe/det/imposto/IPI", "NFe/infNFe/det/imposto/IPI/cEnq",
                                "NFe/infNFe/det/imposto/ISSQN")
    expect(caminhos).not_to include("NFe/infNFe/det/imposto/cEnq")
    expect(caminhos.uniq.size).to eq(caminhos.size), "duplicados: #{caminhos.tally.select { |_, n| n > 1 }.keys.inspect}"
    expect(campos.find { |c| c.tag == "cEnq" }.parent_path).to eq("NFe/infNFe/det/imposto/IPI")
  end

end
