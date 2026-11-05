require "zip"
require "nokogiri"

module Sefaz
  # Extrai o leiaute da NF-e/NFC-e dos esquemas XML oficiais (pacote de liberação espelhado em
  # storage/sefaz/esquemas_xml).
  #
  # Por que o XSD e não o Anexo I: o manual descreve o leiaute para humano, em tabela de PDF cujas
  # colunas mudam de posição a cada página. O esquema é a **fonte normativa** da estrutura e já vem
  # estruturado — traz tipo, tamanho mínimo e máximo, padrão de formato, ocorrência, documentação e,
  # sobretudo, as enumerações com os valores válidos de cada campo. O Anexo I entra depois, para o
  # identificador do manual (B07, I08) e as observações, que o esquema não tem.
  #
  # Devolve uma linha por elemento, com o caminho completo até ele. O mesmo nome de tag aparece em
  # caminhos diferentes (`CNPJ` existe em emitente, destinatário e transportador), e é o caminho que
  # identifica o campo.
  class LayoutExtractor
    Field = Struct.new(:path, :tag, :parent_path, :level, :type, :base_type, :min_length, :max_length,
                       :pattern, :min_occurs, :max_occurs, :documentation, :enumerations, :decimals,
                       keyword_init: true) do
      def to_h
        {
          "tag" => tag, "parent" => parent_path, "level" => level, "type" => type,
          "base_type" => base_type, "min_length" => min_length, "max_length" => max_length,
          "pattern" => pattern, "min_occurs" => min_occurs, "max_occurs" => max_occurs,
          "required" => min_occurs.to_i.positive?, "repeats" => max_occurs != "1",
          "documentation" => documentation, "enumerations" => enumerations.presence,
          "decimals" => decimals
        }.compact
      end
    end

    # Elemento raiz do leiaute da NF-e.
    ROOT = "NFe".freeze

    def self.call(...) = new(...).call

    def initialize(package_path: nil)
      @package_path = package_path
    end

    def call
      load_package
      raiz = @docs.values.filter_map { |doc| doc.at_xpath("//xs:element[@name='#{ROOT}']", XS) }.first
      raise ArgumentError, "elemento #{ROOT} não encontrado no pacote de esquemas" unless raiz

      @fields = []
      walk(raiz, path: ROOT, parent: nil, level: 0)
      @fields.uniq(&:path)
    end

    private

    XS = { "xs" => "http://www.w3.org/2001/XMLSchema" }.freeze

    def load_package
      @docs = {}
      @named_types = {}
      Zip::File.open(package_path) do |zip|
        zip.glob("**/*.xsd").each do |entry|
          next if entry.name.include?("xmldsig") # assinatura: fora do leiaute fiscal
          doc = Nokogiri::XML(entry.get_input_stream.read)
          @docs[File.basename(entry.name)] = doc
          doc.xpath("//xs:simpleType[@name]", XS).each { |t| @named_types[t["name"]] ||= t }
          doc.xpath("//xs:complexType[@name]", XS).each { |t| @named_types[t["name"]] ||= t }
        end
      end
      raise ArgumentError, "pacote sem nenhum esquema (.xsd)" if @docs.empty?
    end

    def package_path
      @package_path ||= begin
        manifest = JSON.parse(File.read(Rails.root.join("db/data/sefaz/manifest.json")))["documentos"]
        melhor = manifest.values.select do |d|
          d["secao"] == "esquemas_xml" && d["arquivo"].to_s.match?(/\APL_\d+\w*_v[\d.]+\.zip\z/i)
        end.max_by { |d| [d["publicado_em"].to_s, d["arquivo"]] }
        melhor && Rails.root.join("storage/sefaz/esquemas_xml", melhor["arquivo"]).to_s
      end
      raise ArgumentError, "pacote de esquemas não encontrado no espelho (rode rake sefaz:sync)" unless @package_path && File.exist?(@package_path)
      @package_path
    end

    # Percorre a árvore do esquema acumulando o caminho. Profundidade limitada para não girar em
    # referência circular de tipo.
    def walk(node, path:, parent:, level:)
      return if level > 12
      @fields << build_field(node, path:, parent:, level:) unless level.zero?

      corpo = complex_body(node)
      return unless corpo

      child_elements(corpo).each do |filho|
        walk(filho, path: "#{path}/#{filho['name']}", parent: path, level: level + 1)
      end
    end

    # Filhos diretos do corpo. `sequence`, `choice` e `all` são conectores e não contam como nível, mas
    # descer indiscriminadamente com `.//` visitaria o mesmo campo várias vezes: o grupo do IPI, por
    # exemplo, aparece dentro de um `choice` e o caminho saía duplicado.
    CONNECTORS = %w[sequence choice all].freeze

    def child_elements(node)
      node.elements.flat_map do |filho|
        if filho.name == "element" && filho["name"]
          [filho]
        elsif CONNECTORS.include?(filho.name)
          child_elements(filho)
        else
          []
        end
      end
    end

    # O corpo pode estar inline (complexType filho) ou num tipo nomeado referenciado por @type.
    def complex_body(node)
      return nil unless node
      inline = node.at_xpath("./xs:complexType", XS)
      return inline if inline
      nome = node["type"]
      tipo = nome && @named_types[nome]
      tipo&.name == "complexType" ? tipo : nil
    end

    def build_field(node, path:, parent:, level:)
      restricao = restriction_for(node)
      Field.new(
        path:, tag: node["name"], parent_path: parent, level:,
        type: node["type"], base_type: restricao&.[]("base"),
        min_length: value_of(restricao, "minLength"), max_length: value_of(restricao, "maxLength"),
        pattern: value_of(restricao, "pattern"), min_occurs: node["minOccurs"] || "1",
        max_occurs: node["maxOccurs"] || "1", documentation: documentation_of(node),
        enumerations: enumerations_of(restricao), decimals: decimals_for(node["type"] || restricao&.[]("base"))
      )
    end

    def restriction_for(node)
      inline = node.at_xpath("./xs:simpleType/xs:restriction", XS)
      return inline if inline
      nome = node["type"]
      tipo = nome && @named_types[nome]
      tipo&.at_xpath("./xs:restriction", XS)
    end

    def value_of(restricao, nome)
      restricao&.at_xpath("./xs:#{nome}", XS)&.[]("value")
    end

    def enumerations_of(restricao)
      Array(restricao&.xpath("./xs:enumeration", XS)).map { |e| e["value"] }.compact
    end

    def documentation_of(node)
      texto = node.at_xpath("./xs:annotation/xs:documentation", XS)&.text
      texto&.gsub(/\s+/, " ")&.strip.presence
    end

    # Os tipos decimais da SEFAZ codificam a escala no nome: TDec_1302 é 13 inteiros e 2 decimais;
    # TDec_0302a04 aceita de 2 a 4 decimais, e aí o que importa é o mínimo.
    def decimals_for(tipo)
      tipo.to_s[/\ATDec_(\d{2})(\d{2})/, 2]&.to_i
    end
  end
end
