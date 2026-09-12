module Audit
  class Finding < ApplicationRecord
    STATES = %w[open justified false_positive fixed ignored].freeze
    STATES_REQUIRING_NOTE = %w[justified false_positive ignored].freeze
    belongs_to :audit_run, class_name: "Audit::AuditRun"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :rule, class_name: "Rules::Rule"
    belongs_to :document, class_name: "Ingestion::Document", optional: true
    belongs_to :fiscal_record, class_name: "Ingestion::FiscalRecord", optional: true
    belongs_to :state_changed_by, class_name: "Accounts::User", optional: true
    validates :state, inclusion: { in: STATES }
    scope :visible, -> { where(shadow: false) }
  end
end
