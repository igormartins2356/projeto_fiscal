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
      others = table.versions.where.not(id: version.id)
      # Comparação contra a publicada E contra o último draft: sem a segunda, o job recriava o mesmo draft todo dia
      # enquanto ninguém publicasse.
      previous = { "published" => others.published.order(version: :desc).first, "draft" => others.where(state: "draft").order(version: :desc).first }
      same_as = previous.find { |_, v| v && fingerprint(v) == fingerprint(version) }&.first
      if same_as
        version.destroy!
        Audit::AuditLog.record!("catalog_sync_unchanged", metadata: { table: table_code, same_as: })
      else
        Audit::AuditLog.record!("catalog_sync_new_draft", subject: version, metadata: { table: table_code, imported: result[:imported] })
      end
    rescue => e
      Audit::AuditLog.record!("catalog_sync_failed", metadata: { table: table_code, error: e.message.first(200) })
      raise
    end

    private

    # Vigência e base legal fazem parte do conteúdo: encerrar a vigência de um NCM/cClassTrib (effective_until)
    # não muda `data` nenhuma e era descartado como "sem mudança".
    # Conjunto ORDENADO de tuplas, não Hash por chave: a mesma chave com duas vigências é legítima (alíquota que
    # muda no meio da versão) e indexar por `key` guardava só uma das linhas — a outra mudava sem ninguém ver.
    def fingerprint(version)
      version.rows.pluck(:key, :data, :effective_from, :effective_until, :legal_basis)
             .map { |key, data, from, till, basis| [Array(key).join("\u0001"), data.to_json, from.to_s, till.to_s, basis.to_s] }.sort
    end
  end
end
