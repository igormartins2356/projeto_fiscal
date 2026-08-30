module Audit
  class AuditLog < ApplicationRecord
    belongs_to :firm, class_name: "Accounts::Firm", optional: true
    belongs_to :user, class_name: "Accounts::User", optional: true

    def self.record!(action, user: nil, firm: nil, subject: nil, ip: nil, **metadata)
      create!(action:, user:, firm: firm || user&.firm, subject_type: subject&.class&.name, subject_id: subject&.id, ip:, metadata:, created_at: Time.current)
    end
  end
end
