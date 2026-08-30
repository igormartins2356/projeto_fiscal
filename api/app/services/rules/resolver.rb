module Rules
  # Regras vigentes para (client, date) com sobreposições aplicadas (ARQUITETURA.md §13).
  # Retorna lista de ResolvedRule { rule:, definition:, source:, override_ids: }.
  class Resolver
    ResolvedRule = Struct.new(:rule, :definition, :source, :override_ids, keyword_init: true)

    def initialize(client:, date:)
      @client = client
      @date = date
    end

    def call
      rules = Rules::Rule.active.effective_on(@date)
                .where(source_type: "platform").or(Rules::Rule.active.effective_on(@date).where(source_type: "firm", source_id: @client.firm_id))
                .order(:code, version: :desc).to_a.uniq(&:code)

      overrides = Rules::RuleOverride.effective_on(@date)
                    .where(source_type: "firm", source_id: @client.firm_id)
                    .or(Rules::RuleOverride.effective_on(@date).where(source_type: "client", source_id: @client.id))
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
            definition = definition.merge(ov.patch.slice("severity", "params", "assert", "applies_when", "message", "let"))
            source = ov.source_type
          when "replace"
            definition = ov.patch.merge("code" => rule.code, "scope" => rule.scope)
            source = ov.source_type
          end
        end
        next if disabled
        ResolvedRule.new(rule:, definition:, source:, override_ids: ids)
      end
    end
  end
end
