require "rails_helper"

# A sincronização é incremental e o manifesto é a prova do que a SEFAZ publicou: os dois pontos são o
# que este spec protege. As respostas do portal são simuladas — sem rede.
RSpec.describe Sefaz::DocumentSync do
  let(:root) { Pathname.new(Dir.mktmpdir) }
  after { FileUtils.rm_rf(root) }

  def http_ok(body, headers = {})
    response = Net::HTTPOK.new("1.1", "200", "OK")
    headers.each { |k, v| response[k] = v }
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  # Página de listagem com um documento por rótulo informado.
  def listagem(*documentos)
    itens = documentos.map do |token, rotulo|
      %(<a href="exibirArquivo.aspx?conteudo=#{token}">#{rotulo}</a>)
    end
    "<html><body>#{itens.join}</body></html>"
  end

  # Subclasse que responde do mapa em vez de abrir conexão. Registra os caminhos pedidos, para o spec
  # poder afirmar que o documento conhecido não foi rebaixado.
  def sync_com(respostas, arquivos, sections: %w[notas_tecnicas], **opts)
    classe = Class.new(described_class) do
      attr_reader :pedidos

      define_method(:start_session) { @pedidos = []; @cookie = "sessao" }
      define_method(:request) do |method, path|
        @pedidos << [method, path]
        chave = [method, path[/conteudo=(.+)\z/, 1] || path[/tipoConteudo=(.+)\z/, 1]]
        respostas.fetch(chave) { raise "sem resposta simulada para #{chave.inspect}" }
      end
    end
    classe.new(root:, sections:, pause: 0, **opts).tap { arquivos }
  end

  let(:token) { "AbC123=" }
  let(:rotulo) { "Nota Técnica 2025.002 v1.40 - RTC. Publicado em 27/07/2026" }
  let(:zip) { "PK\x03\x04conteudo-do-pacote" }

  let(:respostas) do
    {
      [:get, "04BIflQt1aY="] => http_ok(listagem([token, rotulo])),
      [:head, token] => http_ok("", "Content-Length" => zip.bytesize.to_s, "Content-Type" => "application/zip",
                                    "Content-Disposition" => "attachment; filename=NT2025_002_v1.40.zip"),
      [:get, token] => http_ok(zip, "Content-Type" => "application/zip",
                                    "Content-Disposition" => "attachment; filename=NT2025_002_v1.40.zip")
    }
  end

  def manifesto = JSON.parse(File.read(root.join("db/data/sefaz/manifest.json")))

  it "baixa o documento novo, grava o arquivo e registra a procedência no manifesto" do
    resultado = sync_com(respostas, nil).call

    expect(resultado.added).to eq(["notas_tecnicas/#{token}"])
    expect(resultado.sections).to eq("notas_tecnicas" => 1)
    expect(File.binread(root.join("storage/sefaz/notas_tecnicas/NT2025_002_v1.40.zip"))).to eq(zip)

    entrada = manifesto["documentos"]["notas_tecnicas/#{token}"]
    expect(entrada).to include(
      "secao" => "notas_tecnicas", "arquivo" => "NT2025_002_v1.40.zip", "bytes" => zip.bytesize,
      "publicado_em" => "2026-07-27", "sha256" => Digest::SHA256.hexdigest(zip)
    )
    expect(manifesto["sincronizado_em"]).to be_present
  end

  it "não rebaixa documento já conhecido cujo tamanho não mudou" do
    sync_com(respostas, nil).call
    segunda = sync_com(respostas, nil)
    resultado = segunda.call

    expect(resultado.unchanged).to eq(["notas_tecnicas/#{token}"])
    expect(resultado.added).to be_empty
    expect(segunda.pedidos).to include([:head, "/portal/exibirArquivo.aspx?conteudo=AbC123="])
    expect(segunda.pedidos).not_to include([:get, "/portal/exibirArquivo.aspx?conteudo=AbC123="])
  end

  it "rebaixa quando o portal passa a informar outro tamanho" do
    sync_com(respostas, nil).call

    novo = "PK\x03\x04conteudo-do-pacote-revisado"
    alteradas = respostas.merge(
      [:head, token] => http_ok("", "Content-Length" => novo.bytesize.to_s, "Content-Type" => "application/zip",
                                    "Content-Disposition" => "attachment; filename=NT2025_002_v1.40.zip"),
      [:get, token] => http_ok(novo, "Content-Type" => "application/zip",
                                     "Content-Disposition" => "attachment; filename=NT2025_002_v1.40.zip")
    )
    resultado = sync_com(alteradas, nil).call

    expect(resultado.changed).to eq(["notas_tecnicas/#{token}"])
    expect(manifesto["documentos"]["notas_tecnicas/#{token}"]["sha256"]).to eq(Digest::SHA256.hexdigest(novo))
  end

  it "rebaixa quando o arquivo desapareceu do disco, mesmo com o manifesto intacto" do
    sync_com(respostas, nil).call
    FileUtils.rm(root.join("storage/sefaz/notas_tecnicas/NT2025_002_v1.40.zip"))

    resultado = sync_com(respostas, nil).call
    expect(resultado.changed).to eq(["notas_tecnicas/#{token}"])
    expect(File).to exist(root.join("storage/sefaz/notas_tecnicas/NT2025_002_v1.40.zip"))
  end

  it "escapa o espaço que o portal usa no lugar do sinal de mais" do
    com_espaco = "kp0SXLu ZdI="
    mapa = {
      [:get, "04BIflQt1aY="] => http_ok(listagem([com_espaco, "Eventos RTC. Publicado em 01/02/2026"])),
      [:head, "kp0SXLu+ZdI="] => http_ok("", "Content-Length" => zip.bytesize.to_s,
                                             "Content-Disposition" => "attachment; filename=Eventos_RTC.zip"),
      [:get, "kp0SXLu+ZdI="] => http_ok(zip, "Content-Disposition" => "attachment; filename=Eventos_RTC.zip")
    }
    sync = sync_com(mapa, nil)
    expect { sync.call }.not_to raise_error
    expect(sync.pedidos).to include([:head, "/portal/exibirArquivo.aspx?conteudo=kp0SXLu+ZdI="])
  end

  it "registra a falha de um documento e segue com os outros" do
    outro = "XyZ789="
    mapa = respostas.merge(
      [:get, "04BIflQt1aY="] => http_ok(listagem([token, rotulo], [outro, "Documento com problema"])),
      [:head, outro] => Net::HTTPNotFound.new("1.1", "404", "Not Found")
    )
    resultado = sync_com(mapa, nil).call

    expect(resultado.added).to eq(["notas_tecnicas/#{token}"])
    expect(resultado.failed.first).to include("documento" => "notas_tecnicas/#{outro}")
    expect(resultado.failed.first["erro"]).to include("404")
  end

  it "recusa seção desconhecida" do
    expect { sync_com(respostas, nil, sections: %w[inexistente]).call }
      .to raise_error(ArgumentError, /seção desconhecida/)
  end
  # O portal publica três versões do schema de eventos da NT 2025.002 todas como Eventos_RTC.zip.
  it "não deixa um documento sobrescrever o arquivo de outro com o mesmo nome" do
    a, b = "Tok1=", "Tok2="
    zip_a, zip_b = "PK\x03\x04versao-1.40", "PK\x03\x04versao-1.30-diferente"
    cd = "attachment; filename=Eventos_RTC.zip"
    mapa = {
      [:get, "04BIflQt1aY="] => http_ok(listagem([a, "Eventos RTC v1.40. Publicado em 27/07/2026"],
                                                 [b, "Eventos RTC v1.30. Publicado em 07/10/2025"])),
      [:head, a] => http_ok("", "Content-Length" => zip_a.bytesize.to_s, "Content-Disposition" => cd),
      [:get, a] => http_ok(zip_a, "Content-Disposition" => cd),
      [:head, b] => http_ok("", "Content-Length" => zip_b.bytesize.to_s, "Content-Disposition" => cd),
      [:get, b] => http_ok(zip_b, "Content-Disposition" => cd)
    }
    resultado = sync_com(mapa, nil).call
    expect(resultado.added.size).to eq(2)

    docs = manifesto["documentos"]
    nomes = docs.values.map { |d| d["arquivo"] }
    expect(nomes.uniq.size).to eq(2), "dois documentos gravaram no mesmo arquivo: #{nomes.inspect}"

    # Cada resumo tem de corresponder ao conteúdo que está em disco.
    docs.each_value do |d|
      caminho = root.join("storage/sefaz", d["secao"], d["arquivo"])
      expect(Digest::SHA256.file(caminho).hexdigest).to eq(d["sha256"])
    end
    expect(docs.values.map { |d| d["bytes"] }).to contain_exactly(zip_a.bytesize, zip_b.bytesize)
  end

  it "mantém o nome legível quando o portal usa acento, e limpa a seta do rótulo" do
    tok = "Acc1="
    nome = "Anexo I - Leiaute e Regra de Validação - NF-e e NFC-e.pdf"
    pdf = "%PDF-1.4 conteudo"
    mapa = {
      [:get, "04BIflQt1aY="] => http_ok(listagem([tok, "------&gt; Anexo I - Leiaute e Regra de Validação"])),
      [:head, tok] => http_ok("", "Content-Length" => pdf.bytesize.to_s,
                                  "Content-Disposition" => %(attachment; filename="#{nome}").dup.force_encoding("ASCII-8BIT")),
      [:get, tok] => http_ok(pdf, "Content-Disposition" => %(attachment; filename="#{nome}").dup.force_encoding("ASCII-8BIT"))
    }
    resultado = sync_com(mapa, nil).call
    expect(resultado.failed).to be_empty, resultado.failed.inspect
    entrada = manifesto["documentos"]["notas_tecnicas/#{tok}"]
    expect(entrada["arquivo"]).to eq("Anexo_I_-_Leiaute_e_Regra_de_Validacao_-_NF-e_e_NFC-e.pdf")
    expect(entrada["rotulo"]).to eq("Anexo I - Leiaute e Regra de Validação")
  end

end
