module Catalog
  # Sincroniza uma tabela classe A com a fonte oficial: cria versão DRAFT apenas quando há diferença
  # em relação à versão vigente; a publicação continua sendo decisão humana no painel (diff visível).
  class SyncJob < ApplicationJob
    queue_as :catalog

    IMPORTERS = { "ncm" => Catalog::Importers::Ncm, "ibs_cbs_class" => Catalog::Importers::IbsCbsClass }.freeze

    def perform(table_code)
      importer = IMPORTERS[table_code] or raise ArgumentError, "sem importador para #{table_code}"
      table = Catalog::ReferenceTable.find_by!(code: table_code)
      result = importer.new(table).call
      version = result[:version]
      current = table.versions.published.where.not(id: version.id).order(version: :desc).first
      if current && current.rows.pluck(:key, :data).to_h == version.rows.pluck(:key, :data).to_h
        version.destroy!
        Audit::AuditLog.record!("catalog_sync_unchanged", metadata: { table: table_code })
      else
        Audit::AuditLog.record!("catalog_sync_new_draft", subject: version, metadata: { table: table_code, imported: result[:imported] })
      end
    rescue => e
      Audit::AuditLog.record!("catalog_sync_failed", metadata: { table: table_code, error: e.message.first(200) })
      raise
    end
  end
end
