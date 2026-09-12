module Rules
  class RuleOverride < ApplicationRecord
    ACTIONS = %w[disable enable adjust replace].freeze
    # Chaves que um adjust pode trocar e chaves da regra que um replace preserva quando o patch não as informa.
    ADJUSTABLE = %w[severity params assert applies_when message let].freeze
    REPLACE_KEEPS = %w[dsl_version version severity effective_from effective_until].freeze

    belongs_to :created_by, class_name: "Accounts::User"
    validates :override_action, inclusion: { in: ACTIONS }
    validates :source_type, inclusion: { in: %w[firm client] }
    validates :justification, presence: true
    validates :effective_from, presence: true
    # adjust/replace sem patch viram no-op silencioso no Resolver.
    validates :patch, presence: true, if: -> { override_action.in?(%w[adjust replace]) }
    # DSL_RULES §9.1: substituição integral é privilégio da firma. Na validação do model porque no controller
    # a checagem só existia no create — bastava criar um adjust de cliente e trocar a ação por PATCH.
    validate :replace_only_in_firm_scope
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }

    # Composição da definição avaliada. Ponto único: o Resolver (execução) e o controller (validação prévia)
    # tinham cópias divergentes — um patch com `scope` validava com um escopo e rodava com outro.
    def self.compose(definition, rule, override)
      patch = (override.patch || {}).deep_stringify_keys
      case override.override_action
      when "adjust" then definition.merge(patch.slice(*ADJUSTABLE))
      when "replace" then definition.slice(*REPLACE_KEEPS).merge(patch).merge("code" => rule.code, "scope" => rule.scope)
      else definition
      end
    end

    private

    def replace_only_in_firm_scope
      return unless override_action == "replace" && source_type != "firm"
      errors.add(:override_action, "substituição integral só é permitida no escopo da firma")
    end
  end
end
