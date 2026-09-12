module Sefaz
  # Mantém a pasta de documentação oficial da NF-e/NFC-e atualizada (DATA_SOURCES §4).
  # Só registra o que mudou: publicação nova ou documento alterado é o gatilho para revisar regra.
  class SyncJob < ApplicationJob
    queue_as :catalog
    retry_on StandardError, wait: :polynomially_longer, attempts: 3

    def perform(sections = Sefaz::DocumentSync::SECTIONS.keys)
      result = Sefaz::DocumentSync.new(sections: Array(sections)).call
      Audit::AuditLog.record!("sefaz_docs_synced", metadata: {
                                sections: result.sections, added: result.added, changed: result.changed,
                                unchanged: result.unchanged.size, failed: result.failed
                              })
      Rails.logger.info("[sefaz] #{result}")
      result
    end
  end
end
