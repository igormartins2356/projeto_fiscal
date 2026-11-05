require "rails_helper"

# A tabela de regras da SEFAZ tem colunas que mudam de lugar ao longo de 153 páginas, e três
# particularidades que já custaram regra perdida: o typo "Obirg.", o número da coluna colado ao
# identificador, e as regras de consumo indevido, que não têm identificador.
RSpec.describe Sefaz::ValidationRuleExtractor do
  let(:dir) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(dir) }

  def documento(corpo)
    caminho = dir.join("anexo.txt")
    # O extrator só procura a seção 4 depois da linha 150 (antes é sumário).
    File.write(caminho, (["sumário"] * 151).join("\n") + "\n" + corpo)
    caminho
  end

  subject(:regras) { described_class.call(text_path: documento(corpo).to_s) }

  let(:corpo) do
    <<~TXT
      4. Regras de Validação dos Webservices
      4.1.1. Grupo A: Validação do Certificado de Transmissão
           A01      Certificado de Transmissor Inválido:                      Obrig.   280    Rej. Rejeição: Certificado Transmissor inválido
      4.2.1. Autorização de NF-e
                   A. Dados da NF-e
         A03-10       55/65 Campo Id inválido:                                Obrig.   502     Rej. Rejeição: Erro na Chave de Acesso
                            - Chave difere da concatenação dos campos
                            Observação: considerar o CNPJ do emitente
                   C. Emitente
        1C17-40       55/65   Se informada IE do Emitente:                    Obrig.   301   Den.   Uso Denegado: Irregularidade fiscal
         N12a-30      65   NFC-e com CSOSN 103 ou 400 não permitidos           Obirg.   384    Rej. Rejeição: CSOSN não permitido para a UF
      4.3.1. Autorização de NF-e
       55/65 NF-e enviada com mais de 30 rejeições iguais:                     Facul.   656    Rej. Rejeição: Consumo indevido
                                                                                              Página 74 / 153
    TXT
  end

  it "extrai identificador, modelo, código, efeito e mensagem de cada regra" do
    expect(regras.size).to eq(5)
    regra = regras.find { |r| r.id == "A03-10" }
    expect(regra.models).to eq(%w[55 65])
    expect(regra.rejection_code).to eq("502")
    expect(regra.effect).to eq("Rej.")
    expect(regra.message).to include("Erro na Chave de Acesso")
    expect(regra.section).to eq("4.2.1")
    expect(regra.section_title).to eq("A. Dados da NF-e")
  end

  it "acumula a lógica multi-linha da regra, com observação e exceção" do
    regra = regras.find { |r| r.id == "A03-10" }
    expect(regra.rule_text).to include("Campo Id inválido", "concatenação dos campos", "Observação")
  end

  it "classifica pela seção, porque é isso que separa infraestrutura de regra de negócio" do
    expect(regras.find { |r| r.id == "A01" }).to be_infrastructure
    expect(regras.find { |r| r.id == "A03-10" }).to be_business
    expect(regras.find { |r| r.rejection_code == "656" }).to be_improper_use
    expect(regras.map { |r| r.to_h["kind"] }).to include("infraestrutura", "negocio", "consumo_indevido")
  end

  it "tolera o número da coluna colado no identificador, que escondia as denegações" do
    denegacao = regras.find { |r| r.effect == "Den." }
    expect(denegacao.id).to eq("C17-40")
    expect(denegacao.rejection_code).to eq("301")
    expect(denegacao.message).to include("Uso Denegado")
  end

  it "tolera o typo de aplicabilidade que a própria SEFAZ publicou" do
    expect(regras.find { |r| r.id == "N12a-30" }.applicability).to eq("Obrig")
  end

  it "extrai a regra de consumo indevido, que não tem identificador" do
    regra = regras.find { |r| r.rejection_code == "656" }
    expect(regra.id).to eq("MSG656")
    expect(regra.models).to eq(%w[55 65])
    expect(regra.applicability).to eq("Facul")
  end

  it "ignora rodapé de página e recusa documento sem a seção 4" do
    expect(regras.map(&:message).join).not_to include("Página")
    expect { described_class.call(text_path: documento("nada aqui").to_s) }
      .to raise_error(ArgumentError, /seção 4 .*não encontrada/)
  end
  # As notas técnicas da reforma tributária usam a mesma tabela sem a coluna Efeito, com código de
  # quatro dígitos, identificador com ponto (B25.1-10) e "Obrig" sem ponto. Cada uma dessas variações
  # escondia regra: a última chegou a esconder a alíquota do IBS municipal.
  describe "formato da nota técnica" do
    let(:nota) do
      <<~TXT
        Campo Modelo                     Regra de Validação                  Aplic. Msg          Descrição Erro
         B10a-10 65   NFC-e com data de previsão de entrega (tag: dPrevEntrega)      Obrig. 1153 Rejeição: NFC-e com data de previsão
         B25.1-20 55  Se finalidade = 6-Nota de débito (tag:finNFe)                  Obrig. 1009 Rejeição: Não informado tipo de nota
         UB37-10 55/65  Se informado grupo de IBS Municipal (gIBSMun):               Obrig  1036 Rejeição: Alíquota do IBS inválida
      TXT
    end

    subject(:regras) do
      described_class.new(text_path: documento(nota).to_s, source: "NT 2025.002", require_section: false).call
    end

    it "extrai as três, com código de quatro dígitos e a origem registrada" do
      expect(regras.size).to eq(3)
      expect(regras.map(&:rejection_code)).to contain_exactly("1153", "1009", "1036")
      expect(regras.map(&:effect).uniq).to eq(["Rej."])
      expect(regras.map(&:source).uniq).to eq(["NT 2025.002"])
    end

    it "aceita identificador com ponto, que a reforma usa para subcampo" do
      expect(regras.map(&:id)).to include("B25.1-20")
    end

    it "aceita aplicabilidade sem o ponto final, como a SEFAZ publicou" do
      regra = regras.find { |r| r.rejection_code == "1036" }
      expect(regra.id).to eq("UB37-10")
      expect(regra.applicability).to eq("Obrig")
    end

    it "completa a mensagem que começa acima da linha do identificador" do
      texto = <<~TXT
                                                                      Rejeição: CFOP inválido para Nota Fiscal de devolução
         I08-141     55   Para NF-e com as finalidades abaixo:                Obrig. 1179 ou de retorno de mercadoria emitida por MEI
      TXT
      regra = described_class.new(text_path: documento(texto).to_s, require_section: false).call.first
      expect(regra.message).to start_with("Rejeição: CFOP inválido")
      expect(regra.message).to include("retorno de mercadoria emitida por MEI")
    end
  end

end
