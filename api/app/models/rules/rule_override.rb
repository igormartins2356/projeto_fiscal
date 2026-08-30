module Rules
  class RuleOverride < ApplicationRecord
    ACTIONS = %w[disable enable adjust replace].freeze
    belongs_to :created_by, class_name: "Accounts::User"
    validates :override_action, inclusion: { in: ACTIONS }
    validates :source_type, inclusion: { in: %w[firm client] }
    validates :justification, presence: true
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }
  end
end
