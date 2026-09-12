module Ingestion
  # Rederiva o canônico — chamar depois de publicar versão de tabela do Catalog.
  # `client_id` nulo = modo orquestrador: percorre os clientes em lotes e enfileira um job por cliente.
  # O fan-out não pode acontecer dentro do request (publicar uma tabela carregava todos os ids e enfileirava
  # N jobs no ciclo da requisição).
  class RederiveJob < ApplicationJob
    queue_as :ingestion
    discard_on ActiveRecord::RecordNotFound

    def perform(client_id = nil, period_start: nil, period_end: nil)
      return fan_out(period_start, period_end) if client_id.nil?
      client = Accounts::Client.find(client_id)
      Ingestion::Rederive.call(scope_for(client, period_start, period_end))
    end

    private

    def fan_out(period_start, period_end)
      Accounts::Client.select(:id).find_each(batch_size: 200) { |c| self.class.perform_later(c.id, period_start:, period_end:) }
    end

    # Publicar uma tabela vigente a partir de 2026 não pode reprocessar documento de 2024: aquele derivado
    # usou a versão do catálogo vigente na época e continua correto.
    def scope_for(client, period_start, period_end)
      scope = client.documents.fiscal
      scope = scope.where(reference_date: period_start..) if period_start
      scope = scope.where(reference_date: ..period_end) if period_end
      scope
    end
  end
end
