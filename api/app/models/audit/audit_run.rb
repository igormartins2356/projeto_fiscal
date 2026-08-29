module Audit
  class AuditRun < ApplicationRecord
    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :triggered_by, class_name: "Accounts::User", optional: true
    has_many :findings, class_name: "Audit::Finding", foreign_key: :audit_run_id, dependent: :delete_all
  end
end
