module Api
  module V1
    # Linhas de tabela sobrepostas por firma/cliente (alíquota específica, isenção, ST por regime especial).
    class ReferenceRowOverridesController < BaseController
      before_action -> { require_role!("firm_admin") }
      before_action :set_override, only: %i[update destroy]

      def index
        scope = Catalog::ReferenceRowOverride.includes(:reference_table, :created_by)
                  .where(source_type: "firm", source_id: current_firm.id)
                  .or(Catalog::ReferenceRowOverride.where(source_type: "client", source_id: firm_clients.select(:id)))
        scope = scope.where(reference_table_id: params[:reference_table_id]) if params[:reference_table_id].present?
        render json: scope.order(created_at: :desc).map { |o| serialize(o) }
      end

      def create
        o = Catalog::ReferenceRowOverride.new(override_params.merge(created_by: current_user))
        return render json: { error: "cliente não pertence à firma" }, status: :unprocessable_entity unless own_source?(o)
        return render json: { error: "chave com #{o.reference_table.key_arity} parte(s)" }, status: :unprocessable_entity if o.key.size != o.reference_table.key_arity
        o.save!
        audit!("reference_row_override_created", subject: o, table: o.reference_table.code, key: o.key)
        render json: serialize(o), status: :created
      end

      def update
        @override.update!(override_params.except(:reference_table_id, :source_type, :source_id))
        render json: serialize(@override)
      end

      def destroy
        @override.destroy!
        audit!("reference_row_override_deleted", subject: @override)
        head :no_content
      end

      private

      def set_override
        @override = Catalog::ReferenceRowOverride.find(params[:id])
        head :forbidden unless own_source?(@override)
      end

      def own_source?(o)
        (o.source_type == "firm" && o.source_id == current_firm.id) || (o.source_type == "client" && firm_clients.exists?(id: o.source_id))
      end

      def override_params
        p = params.permit(:reference_table_id, :source_type, :source_id, :effective_from, :effective_until, :legal_basis, :justification, key: [])
        p[:data] = params[:data].to_unsafe_h if params[:data].respond_to?(:to_unsafe_h)
        p
      end

      def serialize(o) = o.as_json(only: %i[id reference_table_id source_type source_id key data effective_from effective_until legal_basis justification created_at]).merge(table_code: o.reference_table.code, created_by: o.created_by.name)
    end
  end
end
