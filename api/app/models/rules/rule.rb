module Rules
  class Rule < ApplicationRecord
    SCOPES = %w[item document cross_document period scenario].freeze
    STATES = %w[draft testing shadow published retired].freeze
    SEVERITIES = %w[error warning info].freeze

    belongs_to :created_by, class_name: "Accounts::User", optional: true
    has_many :test_cases, class_name: "Rules::RuleTestCase", foreign_key: :rule_id, dependent: :destroy
    validates :code, :title, :effective_from, presence: true
    validates :version, uniqueness: { scope: :code }
    validates :scope, inclusion: { in: SCOPES }
    validates :state, inclusion: { in: STATES }
    validates :severity, inclusion: { in: SEVERITIES }

    scope :active, -> { where(state: %w[shadow published]) }
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }

    def shadow? = state == "shadow"

    # Definição completa no formato da DSL (DSL_RULES.md §1)
    def definition
      body.merge("code" => code, "version" => version, "scope" => scope, "severity" => severity,
                 "dsl_version" => dsl_version, "effective_from" => effective_from, "effective_until" => effective_until)
    end
  end
end
