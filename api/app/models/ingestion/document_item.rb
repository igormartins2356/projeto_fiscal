module Ingestion
  class DocumentItem < ApplicationRecord
    belongs_to :document, class_name: "Ingestion::Document"
    belongs_to :client, class_name: "Accounts::Client"
  end
end
