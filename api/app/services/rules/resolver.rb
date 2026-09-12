module Rules
  # Regras vigentes para (client, date) com sobreposições aplicadas (ARQUITETURA.md §13).
  # Retorna lista de ResolvedRule { rule:, definition:, source:, override_ids: }.
  class Resolver
    ResolvedRule = Struct.new(:rule, :definition, :source, :override_ids, keyword_init: true)

    attr_reader :warnings

    def initialize(client:, date:)
      @client = client
      @date = date
      @warnings = []
    end

    def call
      # published e shadow coexistem (DSL_RULES §11): a sombra é regra ADICIONAL, não substitui a publicada do mesmo code
      published = scoped_rules.where(state: "published").order(:code, version: :desc).to_a.uniq(&:code)
      shadow = scoped_rules.where(state: "shadow").order(:code, version: :desc).to_a.uniq(&:code)
      rules = published + shadow

      overrides = Rules::RuleOverride.effective_on(@date)
                    .where(source_type: "firm", source_id: @client.firm_id)
                    .or(Rules::RuleOverride.effective_on(@date).where(source_type: "client", source_id: @client.id))
                    .order(:effective_from, :id)   # dois overrides do mesmo escopo: vence o mais recente, sem depender da ordem do banco
                    .group_by(&:rule_code)

      rules.filter_map do |rule|
        definition = rule.definition
        source = rule.source_type
        ids = []
        firm_ov = overrides.fetch(rule.code, []).select { |o| o.source_type == "firm" }
        client_ov = overrides.fetch(rule.code, []).select { |o| o.source_type == "client" }

        disabled = false
        (firm_ov + client_ov).each do |ov|
          ids << ov.id
          case ov.override_action
          when "disable" then disabled = true
          when "enable" then disabled = false if ov.source_type == "client"
          when "adjust"
            definition = Rules::RuleOverride.compose(definition, rule, ov)
            source = ov.source_type
          when "replace"
            # DSL_RULES §9.1: substituição integral é privilégio da firma; override de cliente com replace é ignorado
            if ov.source_type == "client"
              ids.delete(ov.id)
              @warnings << "override #{ov.id} (#{rule.code}): 'replace' só é permitido no escopo da firma — ignorado"
              Rails.logger.warn(@warnings.last)
              next
            end
            # severity/version/vigência continuam vindo da regra quando o patch não os informa
            definition = Rules::RuleOverride.compose(definition, rule, ov)
            source = ov.source_type
          end
        end
        next if disabled
        ResolvedRule.new(rule:, definition:, source:, override_ids: ids)
      end
    end

    private

    def scoped_rules
      Rules::Rule.effective_on(@date).where(source_type: "platform")
        .or(Rules::Rule.effective_on(@date).where(source_type: "firm", source_id: @client.firm_id))
    end
  end
end
