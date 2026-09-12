module Accounts
  class Client < ApplicationRecord
    belongs_to :firm
    # Ordem de declaração = ordem de destruição (LGPD §9, exclusão a pedido): findings apontam para
    # documents/fiscal_records, fiscal_records apontam para documents, documents apontam para upload_batches.
    # `delete_all` onde o filho não tem callback: destruir 500 mil itens um a um levava a exclusão a estourar.
    has_many :findings, class_name: "Audit::Finding", foreign_key: :client_id, dependent: :delete_all
    has_many :fiscal_files, class_name: "Ingestion::FiscalFile", dependent: :destroy
    has_many :document_items, class_name: "Ingestion::DocumentItem", foreign_key: :client_id, dependent: :delete_all
    has_many :documents, class_name: "Ingestion::Document", dependent: :delete_all
    has_many :upload_batches, class_name: "Ingestion::UploadBatch", dependent: :delete_all
    has_many :audit_runs, class_name: "Audit::AuditRun", dependent: :delete_all
    has_many :tax_scenarios, class_name: "Scenario::TaxScenario", dependent: :delete_all
    validates :cnpj, presence: true, length: { is: 14 }, uniqueness: { scope: :firm_id }
    validates :legal_name, :uf, presence: true

    # O que não tem FK para clients não some com o `dependent:` acima: os XML/SPED gravados em disco
    # (Ingestion::XmlStorage e Api::V1::FiscalFilesController) e as sobreposições de escopo cliente, que
    # guardam alíquota e justificativa. Sem isto a exclusão a pedido (LGPD §9) deixava o dado do cliente.
    before_destroy :purge_client_data

    private

    def purge_client_data
      Rules::RuleOverride.where(source_type: "client", source_id: id).delete_all
      Catalog::ReferenceRowOverride.where(source_type: "client", source_id: id).delete_all
      [Rails.root.join("storage", "xml", id.to_s), Rails.root.join("storage", "uploads", id.to_s)].each { |dir| FileUtils.rm_rf(dir) }
    end
  end
end
