require "net/http"
require "digest"

module Sefaz
  # Mantém atualizada a pasta local com a documentação oficial da NF-e/NFC-e publicada no Portal da
  # Nota Fiscal Eletrônica: manuais, esquemas XML, notas técnicas e informes técnicos.
  #
  # Divisão deliberada: os arquivos (centenas de MB) ficam em storage/sefaz, fora do git; o MANIFESTO
  # fica em db/data/sefaz/manifest.json, versionado. Assim o diff do manifesto mostra exatamente o que
  # a SEFAZ publicou ou alterou entre duas sincronizações, que é o gatilho para revisar regra.
  #
  # A sincronização é incremental: a listagem de cada seção é lida sempre, o documento já conhecido só
  # é rebaixado quando o tamanho informado pelo servidor muda.
  class DocumentSync
    HOST = "www.nfe.fazenda.gov.br".freeze
    PORTAL = "/portal/".freeze
    USER_AGENT = "ValidadorFiscal/1.0 (sincronizacao de documentacao publica da NF-e)".freeze

    # Tokens das seções de NF-e/NFC-e no portal (parâmetro tipoConteudo de listaConteudo.aspx).
    # "tabelas_apoio" é a seção que o portal chama de "Diversos": são as tabelas oficiais (CFOP, FCP
    # por UF, municípios, países, classificação do IBS/CBS), que várias regras de validação citam.
    SECTIONS = {
      "manuais" => "ndIjl+iEFdE=",
      "esquemas_xml" => "BMPFMBoln3w=",
      "notas_tecnicas" => "04BIflQt1aY=",
      "informes_tecnicos" => "hXzemuyNHW4=",
      "tabelas_apoio" => "/NJarYc9nus="
    }.freeze

    MAX_BYTES = 200 * 1024 * 1024
    LINK = %r{<a[^>]+href=["'](exibirArquivo\.aspx\?conteudo=[^"']+)["'][^>]*>(.*?)</a>}im
    PUBLICADO_EM = /(?:publicad[oa]|atualizad[oa])\s+em\s+(\d{2})\/(\d{2})\/(\d{2,4})/i

    Result = Struct.new(:added, :changed, :unchanged, :failed, :sections, keyword_init: true) do
      def total = added.size + changed.size + unchanged.size + failed.size
      def to_s
        "novos: #{added.size} | alterados: #{changed.size} | sem mudança: #{unchanged.size} | falhas: #{failed.size}"
      end
    end

    def initialize(root: Rails.root, sections: SECTIONS.keys, download: true, pause: 0.5)
      @manifest_path = root.join("db/data/sefaz/manifest.json")
      @files_root = root.join("storage/sefaz")
      @sections = sections
      @download = download
      @pause = pause
      # Documentos distintos podem ter o mesmo nome de arquivo: o portal publica três versões do
      # schema de eventos da NT 2025.002 todas como Eventos_RTC.zip. Sem reservar o nome por token, uma
      # sobrescreve a outra e o resumo gravado no manifesto passa a não corresponder ao arquivo.
      @reserved = {}
    end

    def call
      manifest = load_manifest
      result = Result.new(added: [], changed: [], unchanged: [], failed: [], sections: {})

      start_session
      @sections.each do |section|
        token = SECTIONS[section] or raise ArgumentError, "seção desconhecida: #{section}"
        documents = list(token)
        result.sections[section] = documents.size
        documents.each { |doc| process(section, doc, manifest, result) }
      end

      save_manifest(manifest)
      result
    ensure
      @http&.finish if @http&.started?
    end

    private

    def start_session
      @http = Net::HTTP.new(HOST, 443)
      @http.use_ssl = true
      @http.open_timeout = 30
      @http.read_timeout = 180
      @http.start
      @cookies = {}
      # O portal redireciona a primeira requisição para negociar o cookie de sessão, e é NA RESPOSTA DE
      # REDIRECIONAMENTO que o Set-Cookie vem: guardar só a resposta final deixa a listagem vazia.
      request(:get, "#{PORTAL}principal.aspx")
    end

    def collect_cookies(response)
      Array(response.get_fields("Set-Cookie")).each do |raw|
        nome, valor = raw.split(";").first.to_s.split("=", 2)
        @cookies[nome.strip] = valor.to_s.strip if nome.present?
      end
    end

    def cookie_header = @cookies.to_a.map { |k, v| "#{k}=#{v}" }.join("; ")

    def request(method, path)
      klass = method == :head ? Net::HTTP::Head : Net::HTTP::Get
      response = nil
      2.times do
        headers = { "User-Agent" => USER_AGENT, "Accept-Language" => "pt-BR,pt;q=0.9" }
        headers["Cookie"] = cookie_header if cookie_header.present?
        response = @http.request(klass.new(path, headers))
        collect_cookies(response)
        break unless response.is_a?(Net::HTTPRedirection) && response["location"].present?
        path = response["location"]
        path = "#{PORTAL}#{path}" unless path.start_with?("/")
      end
      response
    end

    def list(token)
      path = "#{PORTAL}listaConteudo.aspx?tipoConteudo=#{escape(token)}"
      body = request(:get, path).body.to_s.force_encoding("UTF-8").scrub
      seen = {}
      body.scan(LINK).each do |href, label|
        href = CGI.unescapeHTML(href)
        content = href[/conteudo=(.+)\z/, 1].to_s
        next if content.empty? || seen.key?(content)
        seen[content] = { "token" => content, "rotulo" => strip_tags(label) }
      end
      seen.values
    end

    def process(section, doc, manifest, result)
      key = "#{section}/#{doc['token']}"
      known = manifest["documentos"][key]
      head = head_of(doc["token"])
      entry = {
        "secao" => section,
        "token" => doc["token"],
        "rotulo" => doc["rotulo"],
        "arquivo" => head[:filename],
        "bytes" => head[:bytes],
        "content_type" => head[:content_type],
        "publicado_em" => published_on(doc["rotulo"])
      }.compact

      entry["arquivo"] = reserve(section, doc["token"], known&.dig("arquivo") || entry["arquivo"], entry["publicado_em"])

      if known && known["bytes"] == entry["bytes"] && file_present?(section, entry["arquivo"])
        entry["sha256"] = known["sha256"] || digest_of(section, entry["arquivo"])
        entry["coletado_em"] = known["coletado_em"]
        manifest["documentos"][key] = entry.compact
        result.unchanged << key
        return
      end

      if @download
        saved = fetch(section, doc["token"], entry["arquivo"])
        entry.merge!("arquivo" => saved[:filename], "bytes" => saved[:bytes], "sha256" => saved[:sha256])
        sleep(@pause) if @pause.to_f.positive?
      end
      entry["coletado_em"] = Time.current.iso8601
      manifest["documentos"][key] = entry
      (known ? result.changed : result.added) << key
    rescue StandardError => e
      result.failed << { "documento" => key, "rotulo" => doc["rotulo"], "erro" => "#{e.class}: #{e.message}" }
    end

    def head_of(token)
      response = request(:head, "#{PORTAL}exibirArquivo.aspx?conteudo=#{escape(token)}")
      raise "portal respondeu #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      { filename: filename_from(response, token), bytes: response["Content-Length"].to_i,
        content_type: response["Content-Type"].to_s.split(";").first }
    end

    def fetch(section, token, fallback_name)
      response = request(:get, "#{PORTAL}exibirArquivo.aspx?conteudo=#{escape(token)}")
      raise "portal respondeu #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s
      raise "arquivo maior que o limite de #{MAX_BYTES} bytes" if body.bytesize > MAX_BYTES
      raise "portal devolveu HTML no lugar do arquivo" if response["Content-Type"].to_s.include?("text/html")

      name = fallback_name.presence || filename_from(response, token) || "#{safe(token)}.bin"
      dir = @files_root.join(section)
      FileUtils.mkdir_p(dir)
      File.binwrite(dir.join(name), body)
      { filename: name, bytes: body.bytesize, sha256: Digest::SHA256.hexdigest(body) }
    end

    def filename_from(response, token)
      name = response["Content-Disposition"].to_s[/filename\*?=(?:UTF-8'')?"?([^";]+)"?/i, 1]
      name ? safe(name) : nil
    end

    # Nome estável e único por documento: quando dois tokens pedem o mesmo nome, o segundo recebe a
    # data de publicação (que é o que os distingue) ou, na falta dela, um sufixo derivado do token.
    def reserve(section, token, name, published_on)
      name = name.presence || "#{safe(token)}.bin"
      chave = "#{section}/#{name}"
      dono = @reserved[chave]
      return name if dono.nil? || dono == token

      base = File.basename(name, ".*")
      ext = File.extname(name)
      marca = published_on.presence || Digest::SHA256.hexdigest(token)[0, 8]
      alternativo = "#{base}__#{marca}#{ext}"
      @reserved["#{section}/#{alternativo}"] = token
      alternativo
    ensure
      @reserved[chave] ||= token if chave
    end

    def digest_of(section, name)
      caminho = @files_root.join(section, name)
      File.exist?(caminho) ? Digest::SHA256.file(caminho).hexdigest : nil
    end

    def file_present?(section, name)
      name.present? && File.exist?(@files_root.join(section, name))
    end

    def published_on(label)
      m = PUBLICADO_EM.match(label.to_s) or return nil
      year = m[3].length == 2 ? "20#{m[3]}" : m[3]
      Date.new(year.to_i, m[2].to_i, m[1].to_i).iso8601
    rescue Date::Error
      nil
    end

    # O token vem do HTML com espaço no lugar do "+"; o portal aceita as duas formas, mas o espaço
    # precisa ser escapado para não quebrar a requisição.
    def escape(token) = token.gsub(" ", "+").gsub(/[^A-Za-z0-9=+\/_.-]/) { |c| format("%%%02X", c.ord) }

    # Transliterar antes de filtrar: trocar cada acento por "_" deixaria
    # "Leiaute_e_Regra_de_Valida____o" no lugar de "Leiaute_e_Regra_de_Validacao".
    def safe(name)
      # O nome vem do cabeçalho HTTP como ASCII-8BIT: sem rotular como UTF-8, transliterate levanta.
      bruto = name.to_s.dup.force_encoding("UTF-8")
      bruto = bruto.scrub("_") unless bruto.valid_encoding?
      base = ActiveSupport::Inflector.transliterate(File.basename(bruto.strip))
      base.gsub(/[^A-Za-z0-9._+-]/, "_").squeeze("_")[0, 150]
    end

    def strip_tags(html)
      texto = CGI.unescapeHTML(html.to_s.gsub(/<[^>]+>/, " ")).gsub(/\s+/, " ").strip
      # Alguns rótulos do portal vêm com seta de marcação no começo ("------> Anexo I ...").
      texto.sub(/\A[-=>\s]+/, "").strip
    end

    def load_manifest
      return { "documentos" => {} } unless File.exist?(@manifest_path)
      JSON.parse(File.read(@manifest_path)).tap { |m| m["documentos"] ||= {} }
    rescue JSON::ParserError
      { "documentos" => {} }
    end

    def save_manifest(manifest)
      manifest["sincronizado_em"] = Time.current.iso8601
      manifest["fonte"] = "https://#{HOST}#{PORTAL} — seções de NF-e/NFC-e"
      manifest["documentos"] = manifest["documentos"].sort.to_h
      FileUtils.mkdir_p(File.dirname(@manifest_path))
      File.write(@manifest_path, "#{JSON.pretty_generate(manifest)}\n")
    end
  end
end
