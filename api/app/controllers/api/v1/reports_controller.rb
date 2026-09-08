module Api
  module V1
    class ReportsController < BaseController
      before_action :require_client!

      # GET /audit_runs/:audit_run_id/report.pdf
      def audit_run
        run = current_client.audit_runs.find(params[:audit_run_id])
        return render json: { error: "auditoria ainda não concluída" }, status: :unprocessable_entity unless run.state == "done"
        pdf = Reports::AuditRunPdf.new(run)
        audit!("report_generated", subject: run)
        send_data pdf.render, filename: pdf.filename, type: "application/pdf", disposition: "attachment"
      end
    end
  end
end
