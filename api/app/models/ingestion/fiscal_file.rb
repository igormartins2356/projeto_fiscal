module Ingestion
  class FiscalFile < ApplicationRecord
    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :uploaded_by, class_name: "Accounts::User", optional: true
    has_many :records, class_name: "Ingestion::FiscalRecord", foreign_key: :fiscal_file_id, dependent: :delete_all
  end
end
