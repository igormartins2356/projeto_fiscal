module Ingestion
  class UploadBatch < ApplicationRecord
    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :user, class_name: "Accounts::User", optional: true
    has_many :documents, class_name: "Ingestion::Document", foreign_key: :upload_batch_id
  end
end
