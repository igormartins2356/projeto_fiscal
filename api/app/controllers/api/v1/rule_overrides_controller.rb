module Api
  module V1
    # Sobreposições de regra da firma/cliente (firm_admin). Responsabilidade fica registrada (created_by, justification).
    class RuleOverridesController < BaseController
      before_action -> { require_role!("firm_admin") }
      before_action :set_override, only: %i[update destroy]

      def index
        scope = own_scope
        scope = scope.where(rule_code: params[:rule_code]) if params[:rule_code].present?
        render json: scope.order(created_at: :desc).map { |o| serialize(o) }
      end

      def create
        o = Rules::RuleOverride.new(override_params.merge(created_by: current_user))
        return render json: { error: "cliente não pertence à firma" }, status: :unprocessable_entity unless own_source?(o)
        rule = latest_rule(o.rule_code)
        return render json: { error: "regra inexistente" }, status: :unprocessable_entity if rule.nil?
        return render json: { error: "substituição integral só é permitida no escopo da firma" }, status: :unprocessable_entity if o.override_action == "replace" && o.source_type != "firm"
        o.validate!
        errors = definition_errors(rule, o)
        return render json: { error: "sobreposição inválida", errors: }, status: :unprocessable_entity if errors.any?
        o.save!
        audit!("rule_override_created", subject: o, rule_code: o.rule_code, action_kind: o.override_action)
        render json: serialize(o), status: :created
      end

      def update
        @override.assign_attributes(override_params.except(:rule_code, :source_type, :source_id))
        @override.validate!
        errors = definition_errors(latest_rule(@override.rule_code), @override)
        return render json: { error: "sobreposição inválida", errors: }, status: :unprocessable_entity if errors.any?
        @override.save!
        audit!("rule_override_updated", subject: @override)
        render json: serialize(@override)
      end

      def destroy
        @override.destroy!
        audit!("rule_override_deleted", subject: @override, rule_code: @override.rule_code)
        head :no_content
      end

      private

      # O motor só resolve published/shadow (Rules::Resolver): validar contra um draft mais novo valida
      # contra uma definição que nunca vai rodar.
      # Recurso de outra firma responde 404 (403 confirmaria que o id existe).
      def set_override = @override = own_scope.find(params[:id])

      def own_scope
        Rules::RuleOverride.where(source_type: "firm", source_id: current_firm.id)
          .or(Rules::RuleOverride.where(source_type: "client", source_id: firm_clients.select(:id)))
      end

      def own_source?(o)
        (o.source_type == "firm" && o.source_id == current_firm.id) || (o.source_type == "client" && firm_clients.exists?(id: o.source_id))
      end

      def latest_rule(code)
        scope = Rules::Rule.where(code:)
        scope.active.order(version: :desc).first || scope.order(version: :desc).first
      end

      # adjust/replace mudam a definição avaliada: valida o resultado antes de gravar (senão o run inteiro quebra).
      def definition_errors(rule, o)
        return [] if rule.nil? || !o.override_action.in?(%w[adjust replace])
        v = Rules::Validator.new(Rules::RuleOverride.compose(rule.definition, rule, o))
        v.valid?
        v.errors
      end

      def override_params
        p = params.permit(:rule_code, :source_type, :source_id, :override_action, :effective_from, :effective_until, :justification)
        p[:patch] = params[:patch].to_unsafe_h if params[:patch].respond_to?(:to_unsafe_h)
        p
      end

      def serialize(o) = o.as_json(only: %i[id rule_code source_type source_id override_action patch effective_from effective_until justification created_by_id created_at]).merge(created_by: o.created_by.name)
    end
  end
end
