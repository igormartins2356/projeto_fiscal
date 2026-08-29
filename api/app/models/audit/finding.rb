module Audit
  class Finding < ApplicationRecord
    STATES = %w[open justified false_positive fixed ignored].freeze
    belongs_to :audit_run, class_name: "Audit::AuditRun"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :rule, class_name: "Rules::Rule"
    belongs_to :document, class_name: "Ingestion::Document", optional: true
    belongs_to :fiscal_record, class_name: "Ingestion::FiscalRecord", optional: true
    validates :state, inclusion: { in: STATES }
    scope :visible, -> { where(shadow: false) }
  end
end
