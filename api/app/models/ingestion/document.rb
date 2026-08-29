module Ingestion
  class Document < ApplicationRecord
    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :upload_batch, class_name: "Ingestion::UploadBatch", optional: true
    has_many :items, -> { order(:number) }, class_name: "Ingestion::DocumentItem", foreign_key: :document_id, dependent: :delete_all
    has_many :findings, class_name: "Audit::Finding", foreign_key: :document_id

    scope :fiscal, -> { where(kind: %w[nfe nfce]) }
    scope :in_period, ->(from, to) { where(reference_date: from..to) }

    # Canônico completo com itens embutidos (o que o motor enxerga como `doc`)
    def canonical
      data.merge("items" => items.map(&:data))
    end
  end
end
