module Api
  module V1
    # Sobreposições de regra da firma/cliente (firm_admin). Responsabilidade fica registrada (created_by, justification).
    class RuleOverridesController < BaseController
      before_action -> { require_role!("firm_admin") }
      before_action :set_override, only: %i[update destroy]

      def index
        scope = Rules::RuleOverride.where(source_type: "firm", source_id: current_firm.id)
                  .or(Rules::RuleOverride.where(source_type: "client", source_id: firm_clients.select(:id)))
        scope = scope.where(rule_code: params[:rule_code]) if params[:rule_code].present?
        render json: scope.order(created_at: :desc).map { |o| serialize(o) }
      end

      def create
        o = Rules::RuleOverride.new(override_params.merge(created_by: current_user))
        return render json: { error: "cliente não pertence à firma" }, status: :unprocessable_entity unless own_source?(o)
        return render json: { error: "regra inexistente" }, status: :unprocessable_entity unless Rules::Rule.exists?(code: o.rule_code)
        o.save!
        audit!("rule_override_created", subject: o, rule_code: o.rule_code, action_kind: o.override_action)
        render json: serialize(o), status: :created
      end

      def update
        @override.update!(override_params.except(:rule_code, :source_type, :source_id))
        audit!("rule_override_updated", subject: @override)
        render json: serialize(@override)
      end

      def destroy
        @override.destroy!
        audit!("rule_override_deleted", subject: @override, rule_code: @override.rule_code)
        head :no_content
      end

      private

      def set_override
        @override = Rules::RuleOverride.find(params[:id])
        head :forbidden unless own_source?(@override)
      end

      def own_source?(o)
        (o.source_type == "firm" && o.source_id == current_firm.id) || (o.source_type == "client" && firm_clients.exists?(id: o.source_id))
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
