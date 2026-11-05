module Sefaz
  # Extrai as regras de validação e os códigos de rejeição da seção 4 do Anexo I do Manual de
  # Orientação ao Contribuinte (espelhado em storage/sefaz/manuais). É a tabela que a SEFAZ aplica na
  # autorização, e a fonte do que o contador vê quando a nota é rejeitada.
  #
  # A extração é ancorada no padrão mais distintivo da linha — aplicabilidade, código de três dígitos
  # e efeito — e não em posição de coluna: as colunas mudam de lugar ao longo das 153 páginas, e
  # fatiar por posição saiu desalinhado quando tentamos isso no leiaute.
  #
  # A seção de origem é guardada porque decide a classificação: o que está em 4.1 é infraestrutura
  # (certificado, assinatura, schema) e não vira regra do validador; o que está em 4.2 é regra de
  # negócio, que é o que interessa.
  class ValidationRuleExtractor
    # `topic` é o módulo do documento de origem (eventos, reforma, leiaute...). Não vem do texto: é
    # quem chama que sabe qual nota está lendo, e é o que permite priorizar — rejeição de evento só
    # interessa a quem emite, não a quem valida XML recebido.
    Rule = Struct.new(:id, :group, :models, :rule_text, :applicability, :rejection_code, :effect,
                      :message, :section, :section_title, :source, :topic, keyword_init: true) do
      def infrastructure? = section.to_s.start_with?("4.1")
      def business? = section.to_s.start_with?("4.2")
      def improper_use? = section.to_s.start_with?("4.3")

      def to_h
        {
          "id" => id, "group" => group, "models" => models, "rule_text" => rule_text,
          "applicability" => applicability, "effect" => effect, "message" => message,
          "section" => section, "section_title" => section_title, "source" => source, "topic" => topic,
          "kind" => if infrastructure? then "infraestrutura"
                    elsif improper_use? then "consumo_indevido"
                    else "negocio"
                    end
        }.compact
      end
    end

    # Variações que a própria SEFAZ publicou e que, sem tolerância, fazem a regra se perder: o typo
    # "Obirg." no Anexo I, e "Obrig" sem o ponto na nota técnica da reforma (regra UB37-10).
    APPLICABILITY = /Obrig\.?|Obirg\.?|Facul\.?|Opc\.?|N\/A/
    EFFECT = /Rej\.|Den\.|Adv\./
    # A03-10, BA12-20, ZX04-100, N12a-30, e o caso sem sequência (A01). O prefixo numérico opcional é
    # a coluna "#" da tabela, que o PDF cola no identificador: "1C17-40" é a regra C17-40, e sem
    # tolerar isso as três regras de denegação por irregularidade fiscal se perdiam.
    # A nota técnica da reforma numera subcampos com ponto: B25.1-10, B25.2-30.
    # A letra maiúscula no fim é revisão intercalada: P12-30A entra entre P12-26 e P12-34, e sem
    # tolerá-la a regra de modelo diferente de 55 (rejeição 450) se perdia.
    RULE_ID = /[A-Z]{1,3}\d{2,3}(?:\.\d+)?[a-z]?(?:-\d+)?[A-Z]?/
    # O código tem 3 dígitos no Anexo I e 4 nas rejeições da reforma tributária (1153, 1154...).
    CODE = /\d{3,4}/
    LINE = /\A\s*\d{0,3}(#{RULE_ID})\s+(\d{2}(?:\/\d{2})?)?\s*(.*?)\s+(#{APPLICABILITY})\s+(#{CODE})\s+(#{EFFECT})\s*(.*)\z/
    # As regras de consumo indevido (4.3) não têm identificador: começam pelo modelo.
    LINE_WITHOUT_ID = /\A\s*(\d{2}(?:\/\d{2})?)\s+(.*?)\s+(#{APPLICABILITY})\s+(#{CODE})\s+(#{EFFECT})\s*(.*)\z/
    # Uma regra pode listar várias condições, cada uma com seu próprio código e mensagem, em linhas
    # que não repetem o identificador nem o modelo. São regras de fato — a condição "existe evento de
    # registro de passagem" tem código 219 e mensagem própria — e herdam o identificador da regra que
    # estão detalhando. A chave do catálogo é identificador + código, então convivem sem colidir.
    # Quando a regra que está sendo detalhada não tem código próprio (a linha "GA09 Acessar ao BD de
    # Eventos" só abre a lista), não há identificador para herdar e vale a convenção da seção 4.3:
    # identificador sintético a partir do código.
    # A mensagem pode estar vazia na linha da condição — a célula do PDF põe o texto na linha de cima —
    # e aí o efeito é o último token. Sem separar os dois, "Rej." virava a mensagem da rejeição 494.
    LINE_CONDITION = /\A\s{2,}(\S.*?)\s+(#{APPLICABILITY})\s+(#{CODE})(?:\s+(#{EFFECT}))?\s*(.*)\z/

    # A nota técnica usa a mesma tabela, mas sem a coluna Efeito: a mensagem já começa com "Rejeição:".
    # A mensagem pode vir vazia ou truncada na linha do identificador, porque a célula do PDF é
    # centralizada verticalmente e o texto se distribui acima e abaixo. O que identifica a regra é o
    # trio identificador, aplicabilidade e código; a mensagem é completada pelas continuações.
    LINE_WITHOUT_EFFECT = /\A\s*\d{0,3}(#{RULE_ID})\s+(\d{2}(?:\/\d{2})?)?\s*(.*?)\s+(#{APPLICABILITY})\s+(#{CODE})\s*(.*)\z/
    SECTION = /\A\s*(4(?:\.\d+){1,2})\.\s+(\S.*)\z/
    GROUP_TITLE = /\A\s{6,}([A-Z]{1,2})\.\s+(\S.{3,60})\z/
    FOOTER = /Página\s+\d+\s*\/|\AMOC\s|\ANota Fiscal Eletrônica\z/

    def self.call(...) = new(...).call

    def initialize(text_path: nil, pdf_path: nil, source: nil, topic: nil, require_section: true)
      @text_path = text_path
      @pdf_path = pdf_path
      @source = source
      @topic = topic
      @require_section = require_section
    end

    def call
      linhas = text.split("\n")
      @source ||= File.basename(text_path, ".txt")
      inicio = linhas.each_index.find { |i| i > 150 && linhas[i].match?(/\A\s*4\.\s+Regras de Valida/) }
      # A nota técnica não tem a seção 4 do manual: a tabela de regras aparece ao longo do documento.
      raise ArgumentError, "seção 4 (regras de validação) não encontrada no documento" if @require_section && !inicio
      inicio ||= 0

      regras = []
      secao = nil
      titulo_grupo = nil
      atual = nil

      (inicio...linhas.size).each do |i|
        linha = linhas[i]
        next if linha.match?(FOOTER)
        @linhas = linhas
        @indice = i

        if (m = SECTION.match(linha))
          secao = m[1]
          titulo_grupo = nil
          next
        end
        if (m = GROUP_TITLE.match(linha)) && !linha.match?(EFFECT)
          titulo_grupo = "#{m[1]}. #{m[2].strip}"
          next
        end

        if (m = LINE.match(linha))
          atual = Rule.new(
            id: m[1], group: m[1][/\A[A-Z]+/], models: models_of(m[2]), rule_text: m[3].to_s.strip,
            applicability: normalize_applicability(m[4]), rejection_code: m[5], effect: m[6],
            message: strip_effect_leftover(m[7]), section: secao, section_title: titulo_grupo, source: @source, topic: @topic
          )
          regras << atual
        elsif (m = LINE_WITHOUT_ID.match(linha))
          atual = Rule.new(
            id: "MSG#{m[4]}", group: nil, models: models_of(m[1]), rule_text: m[2].to_s.strip,
            applicability: normalize_applicability(m[3]), rejection_code: m[4], effect: m[5],
            message: strip_effect_leftover(m[6]), section: secao, section_title: titulo_grupo, source: @source, topic: @topic
          )
          regras << atual
        elsif (m = LINE_WITHOUT_EFFECT.match(linha))
          atual = Rule.new(
            id: m[1], group: m[1][/\A[A-Z]+/], models: models_of(m[2]), rule_text: m[3].to_s.strip,
            applicability: normalize_applicability(m[4]), rejection_code: m[5], effect: "Rej.",
            message: message_with_lookback(m[6].to_s.strip, linha), section: secao,
            section_title: titulo_grupo, source: @source, topic: @topic
          )
          regras << atual
        elsif (m = LINE_CONDITION.match(linha)) && m[3] != atual&.rejection_code
          # Condição adicional da regra corrente: mesmo identificador, código e mensagem próprios.
          atual = Rule.new(
            id: inherited_id(atual, m[3]), group: atual&.group, models: atual&.models || [],
            rule_text: m[1].to_s.strip,
            applicability: normalize_applicability(m[2]), rejection_code: m[3],
            effect: m[4] || "Rej.", message: message_with_lookback(m[5].to_s.strip, linha),
            section: secao, section_title: titulo_grupo, source: @source, topic: @topic
          )
          regras << atual
        elsif atual
          append_continuation(atual, linha)
        end
      end

      regras
    end

    private

    def models_of(texto)
      return [] if texto.blank?
      texto.split("/").map(&:strip).select { |m| m.match?(/\A\d{2}\z/) }
    end

    # A célula da mensagem é centralizada verticalmente no PDF: quando a regra ocupa várias linhas, o
    # começo da mensagem aparece ACIMA da linha do identificador. Sem olhar para trás, a mensagem sai
    # truncada no meio de uma frase ("ou de retorno de mercadoria emitida por MEI").
    def message_with_lookback(mensagem, linha)
      mensagem = strip_effect_leftover(mensagem)
      return mensagem if mensagem.match?(/\ARejei|\AUso Den/i)

      # Não exige alinhamento exato de coluna: basta que a linha anterior tenha o começo da mensagem
      # à direita do texto da regra. Exigir a mesma coluna falhava quando o PDF desloca a célula.
      anteriores = (1..3).filter_map do |passo|
        candidata = @linhas[@indice - passo].to_s
        posicao = candidata.index(/Rejei\S*|Uso Denegado/i)
        next unless posicao && posicao > 40
        candidata[posicao..].to_s.strip.presence
      end
      return mensagem if anteriores.empty?
      [anteriores.last, mensagem].reject(&:blank?).join(" ").strip
    end

    # A condição herda o identificador da regra que detalha. Quando essa regra também não tinha
    # identificador (já é sintético), herdar propagaria o código errado: MSG221 para a rejeição 219.
    def inherited_id(atual, codigo)
      return "MSG#{codigo}" if atual.nil? || atual.id.to_s.start_with?("MSG")
      atual.id
    end

    def normalize_applicability(valor) = valor.to_s.sub("Obirg.", "Obrig.").delete(".").strip

    # A coluna Efeito às vezes perde o ponto ("Rej" em vez de "Rej.") e então entra na mensagem, que
    # sai como "Rej   Rejeição: Valor do FCP...". Só remove quando o que sobra é a mensagem de fato.
    EFFECT_LEFTOVER = /\A(?:Rej|Den|Adv|R)\.?\s+(?=Rejei|Uso Den)/i

    # Quando a coluna Efeito sem ponto é tudo o que sobra, ela não é mensagem nenhuma: a NT 2011.006
    # não tem coluna de descrição do erro, só código.
    def strip_effect_leftover(mensagem)
      texto = mensagem.to_s.sub(EFFECT_LEFTOVER, "").strip
      texto.match?(/\A(?:Rej|Den|Adv)\.?\z/) ? "" : texto
    end

    # Linha de continuação: o texto da regra segue à esquerda e a mensagem à direita. Sem a coluna
    # para separar, o critério é a posição: o que está bem à direita continua a mensagem.
    # Uma linha de continuação pode trazer texto de regra à esquerda E o começo da mensagem à direita,
    # separados por um vão de espaços — é assim que a mensagem da rejeição 246 (E17-70) aparece, três
    # linhas depois da regra. Tratar a linha inteira como uma coisa só perdia a mensagem.
    MESSAGE_TAIL = /\s{3,}((?:Rejei\S*|Uso Denegado).*)\z/

    def append_continuation(regra, linha)
      texto = linha.strip
      return if texto.empty?

      if (m = MESSAGE_TAIL.match(linha)) && m.begin(1) > 60
        regra.message = [regra.message, m[1].strip].reject(&:blank?).join(" ")
        esquerda = linha[0...m.begin(0)].strip
        regra.rule_text = [regra.rule_text, esquerda].reject(&:blank?).join("\n") if esquerda.present?
      elsif linha[/\A\s*/].size > 100
        regra.message = [regra.message, texto].reject(&:blank?).join(" ")
      else
        regra.rule_text = [regra.rule_text, texto].reject(&:blank?).join("\n")
      end
    end

    def text
      return File.read(text_path) if text_path && File.exist?(text_path)
      raise ArgumentError, "texto do Anexo I não disponível: informe text_path ou pdf_path"
    end

    # O texto fica em cache ao lado do espelho, porque extrair 153 páginas a cada chamada é caro.
    # `poppler-utils` (pdftotext) é dependência da imagem; se faltar, a mensagem diz o que instalar.
    def text_path
      @text_path ||= begin
        pdf = pdf_path
        destino = Rails.root.join("storage/sefaz/texto/manuais", "#{File.basename(pdf, '.pdf')}.txt")
        unless File.exist?(destino) && File.mtime(destino) > File.mtime(pdf)
          FileUtils.mkdir_p(File.dirname(destino))
          ok = system("pdftotext", "-layout", pdf.to_s, destino.to_s, out: File::NULL, err: File::NULL)
          raise ArgumentError, "pdftotext não disponível na imagem: instale poppler-utils" unless ok && File.exist?(destino)
        end
        destino.to_s
      end
    end

    def pdf_path
      @pdf_path ||= begin
        manifest = JSON.parse(File.read(Rails.root.join("db/data/sefaz/manifest.json")))["documentos"]
        melhor = manifest.values.find do |d|
          d["secao"] == "manuais" && d["arquivo"].to_s.match?(/ANEXO_I.*Regra.*\.pdf\z/i)
        end
        melhor && Rails.root.join("storage/sefaz/manuais", melhor["arquivo"]).to_s
      end
      raise ArgumentError, "Anexo I não encontrado no espelho (rode rake sefaz:sync)" unless @pdf_path && File.exist?(@pdf_path)
      @pdf_path
    end
  end
end
