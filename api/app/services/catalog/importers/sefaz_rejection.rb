module Catalog
  module Importers
    # Importa para o catálogo a tabela de regras de validação e códigos de rejeição da SEFAZ,
    # extraída do Anexo I do manual (`Sefaz::ValidationRuleExtractor`).
    #
    # É o que permite dizer ao contador "a SEFAZ rejeitaria isso com o código 327", que é a dor
    # declarada do produto, e classificar com honestidade o que é redundante com a autorização.
    #
    # A chave é o par identificador + código. Nenhum dos dois basta sozinho: o mesmo código serve a
    # regras diferentes (478 códigos para 551 regras), e o mesmo identificador também — B09-10 cobre
    # tanto "emissão posterior ao recebimento" (703) quanto "emissão anterior ao credenciamento" (479),
    # porque o identificador aponta o campo, não a condição. Chavear só pelo identificador descartava
    # 36 regras em silêncio.
    class SefazRejection
      TABLE_CODE = "sefaz_rejeicao".freeze
      SOURCE = "Portal da NF-e — MOC 7.0, Anexo I, seção 4 (Regras de Validação)".freeze
      LEGAL_BASIS = "Manual de Orientação ao Contribuinte, Anexo I — Regras de Validação".freeze

      # Documentos que compõem o catálogo: o Anexo I traz a tabela consolidada, e cada nota técnica
      # acrescenta as regras do seu tema. A da reforma tributária é a maior fonte fora do manual.
      #
      # As notas de eventos são a segunda maior fonte, e nenhuma das suas rejeições está no Anexo I:
      # o manual valida a NF-e, não o evento. São 476 regras que só existem aqui, e todas valem para
      # quem emite ou cancela — por isso o tema `eventos`, que separa o que é do validador de XML
      # recebido do que é de uma futura emissão (ver docs/EMISSAO_NFE.md).
      #
      # Só a versão vigente de cada nota entra. A NT 2024.002 fica de fora porque foi absorvida pela
      # 2025.002 (105 dos seus 107 códigos já estão lá).
      #
      # As notas de eventos republicam a tabela comum de validação do evento, então a mesma regra
      # (P10-20, rejeição 494) aparece em quatro delas. `nt` ordena a deduplicação: prevalece a nota
      # mais recente, que é a que tem o texto vigente. Sem isso, a versão de 2011 — publicada sem a
      # coluna de descrição do erro — vencia a de 2023 e a mensagem se perdia.
      NOTES = [
        { nt: "2025.002", file: "NT_2025.002_v1.51_RTC.txt", source: "NT 2025.002 v1.51 — reforma tributária", topic: "reforma" },
        { nt: "2026.006", file: "NT_2026.006_v1.00_RTC_VinculacaoPagamento_2775_.txt", source: "NT 2026.006 v1.00 — vinculação de pagamento", topic: "reforma" },
        { nt: "2011.006", file: "NT2011.006c_Evento_Cancelamento.txt", source: "NT 2011.006 c — evento de cancelamento", topic: "eventos" },
        { nt: "2013.008", file: "NT2013_008_v1_00_Cancelamento_NFe.txt", source: "NT 2013.008 v1.00 — cancelamento com evento posterior", topic: "eventos" },
        { nt: "2014.001", file: "NT_2014_001_v1.41_-_Evento_EPEC.txt", source: "NT 2014.001 v1.41 — EPEC", topic: "eventos" },
        { nt: "2014.004", file: "NT2014.004_v1.10_NCM_Pais_Fuso_Evento.txt", source: "NT 2014.004 v1.10 — NCM, país e fuso", topic: "eventos" },
        { nt: "2018.004", file: "NT_2018_004_-_Cancelamento_por_Substituicao_da_NFC-e.txt", source: "NT 2018.004 — cancelamento por substituição da NFC-e", topic: "eventos" },
        { nt: "2020.001", file: "NT_2020.001_v1.60_-_Manifestacao_do_destinatario.txt", source: "NT 2020.001 v1.60 — manifestação do destinatário", topic: "eventos" },
        { nt: "2020.007", file: "NT2020.007_v1.40_-_Evento_Ator_NFe_Transportador.txt", source: "NT 2020.007 v1.40 — ator interessado, transportador", topic: "eventos" },
        { nt: "2021.001", file: "NT_2021_001_v1.01_Evento_Comprovante_Entrega_NFe.txt", source: "NT 2021.001 v1.01 — comprovante de entrega", topic: "eventos" },
        { nt: "2023.005", file: "NT2023.005_v1.02_-_Evento_Insucesso_Entrega_NF-e.txt", source: "NT 2023.005 v1.02 — insucesso na entrega", topic: "eventos" },
        { nt: "2013.001", file: "NT2013.001_Manifestacao_Combustivel.txt", source: "NT 2013.001 — manifestação e combustível", topic: "eventos" }
      ].freeze

      def initialize(table = nil, rules: nil, include_notes: true)
        @table = table || find_or_create_table
        @rules = rules
        @include_notes = include_notes
      end

      def call(user: nil)
        rules = @rules || collect_rules
        raise ArgumentError, "nenhuma regra de validação extraída do Anexo I" if rules.empty?

        version = nil
        Catalog::ReferenceVersion.transaction do
          last = @table.versions.order(version: :desc).first
          version = @table.versions.create!(
            version: (last&.version || 0) + 1, state: "draft", source_url: SOURCE, imported_by: user,
            effective_from: [@table.versions.published.minimum(:effective_from), Date.current].compact.min,
            notes: "#{rules.size} regras, #{rules.map(&:rejection_code).uniq.size} códigos de rejeição; " \
                   "por origem: #{rules.group_by(&:source).transform_values(&:size).map { |k, v| "#{k}=#{v}" }.join(', ')}"
          )
          linhas = rules.uniq { |r| [r.id, r.rejection_code] }
          mensagens = messages_by_code(linhas)
          Catalog::ReferenceRow.insert_all!(linhas.map do |rule|
            { reference_version_id: version.id, key: [rule.id, rule.rejection_code],
              data: rule.to_h.merge("code" => rule.rejection_code).merge(backfilled_message(rule, mensagens)),
              legal_basis: LEGAL_BASIS }
          end)
        end
        { version:, imported: version.rows.count, codes: rules.map(&:rejection_code).uniq.size,
          business: rules.count(&:business?) }
      end

      private

      # A NT 2011.006 publica a tabela de regras dos eventos sem a coluna de descrição do erro: traz o
      # código e nada mais. A mensagem existe, só está em outro documento oficial — a rejeição 280 é
      # "Certificado Transmissor inválido" na NT 2014.001. Completar pelo código recupera 62 das 66
      # mensagens ausentes; as 4 que sobram são de infraestrutura (SOAP header) e o texto da regra já
      # diz tudo. A origem fica registrada para o contador saber de onde veio o texto.
      def messages_by_code(rules)
        rules.reject { |r| r.message.to_s.strip.empty? }
             .group_by(&:rejection_code)
             .transform_values { |v| { message: v.first.message, source: v.first.source } }
      end

      def backfilled_message(rule, mensagens)
        return {} unless rule.message.to_s.strip.empty?
        achado = mensagens[rule.rejection_code]
        return {} unless achado
        { "message" => achado[:message], "message_source" => achado[:source] }
      end

      def collect_rules
        manual = Sefaz::ValidationRuleExtractor.new(source: "MOC 7.0 Anexo I", topic: "manual").call
        return manual unless @include_notes

        base = Rails.root.join("storage/sefaz/texto/notas_tecnicas")
        notas = NOTES.sort_by { |n| n[:nt] }.reverse.flat_map do |nota|
          caminho = base.join(nota[:file])
          next [] unless File.exist?(caminho)
          Sefaz::ValidationRuleExtractor.new(text_path: caminho.to_s, source: nota[:source],
                                             topic: nota[:topic], require_section: false).call
        end
        # O Anexo I é a fonte consolidada e prevalece; a nota acrescenta o que ainda não está lá.
        conhecidos = manual.map { |r| [r.id, r.rejection_code] }.to_set
        manual + notas.reject { |r| conhecidos.include?([r.id, r.rejection_code]) }
      end

      def find_or_create_table
        Catalog::ReferenceTable.find_or_create_by!(code: TABLE_CODE) do |t|
          t.name = "Regras de validação e rejeições da SEFAZ"
          t.key_names = %w[rule_id code]
          t.key_arity = 2
          t.source_class = "A"
          t.source_url = SOURCE
        end
      end
    end
  end
end
