module Audit
  class AuditRun < ApplicationRecord
    STATES = %w[queued running done failed].freeze

    belongs_to :firm, class_name: "Accounts::Firm"
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :triggered_by, class_name: "Accounts::User", optional: true
    has_many :findings, class_name: "Audit::Finding", foreign_key: :audit_run_id, dependent: :delete_all

    validates :state, inclusion: { in: STATES }
    validates :period_start, :period_end, presence: true
    validate :period_in_order
    # o run atravessa firma e cliente (findings, PDF, escopo por firm_clients): divergir aqui vaza dado entre escritórios
    validate :firm_matches_client

    private

    def period_in_order
      return if period_start.blank? || period_end.blank?
      errors.add(:period_end, "deve ser igual ou posterior ao início do período") if period_end < period_start
    end

    def firm_matches_client
      return if firm_id.blank? || client.blank?
      errors.add(:firm_id, "não é a firma do cliente") if firm_id != client.firm_id
    end
  end
end
