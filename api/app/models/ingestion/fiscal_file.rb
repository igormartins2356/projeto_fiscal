module Ingestion
  class FiscalFile < ApplicationRecord
    KINDS = %w[sped_icms_ipi sintegra].freeze
    STATES = %w[pending parsing done failed].freeze
    PURPOSES = %w[original rectifying].freeze

    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :upload_batch, class_name: "Ingestion::UploadBatch", optional: true
    belongs_to :uploaded_by, class_name: "Accounts::User", optional: true
    has_many :records, class_name: "Ingestion::FiscalRecord", foreign_key: :fiscal_file_id, dependent: :delete_all

    validates :kind, inclusion: { in: KINDS }
    validates :state, inclusion: { in: STATES }
    validates :purpose, inclusion: { in: PURPOSES }, allow_nil: true
  end
end
