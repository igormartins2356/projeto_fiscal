module Ingestion
  class FiscalRecord < ApplicationRecord
    belongs_to :fiscal_file, class_name: "Ingestion::FiscalFile"
    belongs_to :document, class_name: "Ingestion::Document", optional: true
  end
end
