module Api
  module V1
    # Listagem paginada server-side (DataTable lazy): page, per_page, sort_field, sort_order, filtros por coluna.
    class FindingsController < BaseController
      before_action :require_client!
      SORTABLE = %w[rule_code severity state item_number created_at].freeze

      def index
        run = current_client.audit_runs.find(params[:audit_run_id])
        scope = run.findings.visible.includes(:document, :rule)
        scope = scope.where(rule_code: params[:rule_code]) if params[:rule_code].present?
        scope = scope.where(severity: params[:severity]) if params[:severity].present?
        scope = scope.where(state: params[:state]) if params[:state].present?
        scope = scope.where(document_id: params[:document_id]) if params[:document_id].present?
        scope = scope.where("findings.message ILIKE ?", "%#{Audit::Finding.sanitize_sql_like(params[:q])}%") if params[:q].present?

        field = SORTABLE.include?(params[:sort_field]) ? params[:sort_field] : "rule_code"
        dir = params[:sort_order].to_s == "-1" || params[:sort_order].to_s == "desc" ? :desc : :asc
        scope = scope.order(field => dir, :document_id => :asc, :item_number => :asc)

        per_page = params.fetch(:per_page, 25).to_i.clamp(1, 200)
        page = [params.fetch(:page, 1).to_i, 1].max
        total = scope.count
        rows = scope.offset((page - 1) * per_page).limit(per_page)
        render json: { data: rows.map { |f| serialize(f) }, total:, page:, per_page: }
      end

      def update
        f = Audit::Finding.where(client: current_client).find(params[:id])
        f.update!(state: params.require(:state), state_note: params[:state_note], state_changed_at: Time.current)
        render json: serialize(f)
      end

      private

      def serialize(f)
        f.as_json(except: [:evidence]).merge(
          evidence: f.evidence,
          rule_title: f.rule.title,
          document: f.document && { id: f.document.id, access_key: f.document.access_key, number: f.document.number, series: f.document.series,
                                    issued_at: f.document.issued_at, nature: f.document.operation_nature, model: f.document.model }
        )
      end
    end
  end
end
