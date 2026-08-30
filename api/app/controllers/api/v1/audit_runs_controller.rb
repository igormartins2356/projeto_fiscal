module Api
  module V1
    class AuditRunsController < BaseController
      before_action :require_client!
      def index
        render json: current_client.audit_runs.order(created_at: :desc).limit(50)
      end

      def create
        run = current_client.audit_runs.create!(firm_id: current_client.firm_id, period_start: params.require(:period_start), period_end: params.require(:period_end))
        Audit::RunJob.perform_later(run.id)
        render json: run, status: :created
      end

      def show
        run = current_client.audit_runs.find(params[:id])
        render json: run.as_json.merge(
          summary: run.findings.visible.group(:severity).count,
          groups: run.findings.visible.group(:rule_code, :severity, :group_key).count.map { |(code, sev, gk), n| { rule_code: code, severity: sev, group_key: gk, count: n } }
        )
      end
    end
  end
end
