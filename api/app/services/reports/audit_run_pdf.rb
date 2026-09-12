module Reports
  # Relatório da auditoria em PDF com a marca do escritório (PROJECT_SCOPE fase 3):
  # produto que o contador entrega/revende ao cliente dele.
  class AuditRunPdf
    SEVERITY_LABEL = { "error" => "Erros", "warning" => "Alertas", "info" => "Informativos" }.freeze

    def initialize(run) = @run = run

    def render
      html = ActionController::Base.render(template: "reports/audit_run", layout: "pdf", assigns: build_assigns)
      WickedPdf.new.pdf_from_string(html, page_size: "A4", margin: { top: 12, bottom: 14, left: 12, right: 12 },
                                    footer: { font_size: 7, right: "[page]/[topage]", left: "Gerado em #{generated_at}" })
    end

    def filename = "auditoria-#{@run.client.legal_name.parameterize}-#{@run.period_start.strftime('%Y-%m')}-run#{@run.id}.pdf"

    private

    def generated_at
      I18n.l(Time.current, format: :short)
    rescue I18n::ArgumentError, I18n::MissingTranslationData
      Time.current.strftime("%d/%m/%Y %H:%M")
    end

    def build_assigns
      findings = @run.findings.visible.includes(:document, :rule)
      by_severity = findings.group(:severity).count
      groups = findings.group_by(&:rule_code).map do |code, fs|
        rule = fs.first.rule
        top = fs.group_by(&:group_key).map { |gk, list| { key: gk, count: list.size, sample: list.first } }.sort_by { |g| -g[:count] }.first(5)
        { code:, rule:, count: fs.size, severity: fs.first.severity, source: fs.first.rule_source, top_groups: top,
          samples: fs.reject { |f| f.state != "open" }.first(8), states: fs.group_by(&:state).transform_values(&:size) }
      end.sort_by { |g| [{ "error" => 0, "warning" => 1, "info" => 2 }[g[:severity]] || 3, -g[:count]] }
      docs = @run.client.documents.fiscal.in_period(@run.period_start, @run.period_end)
      {
        run: @run, client: @run.client, firm: @run.firm, by_severity:, groups:,
        docs_stats: { total: docs.count, cancelled: docs.where(status_state: "cancelled").count },
        severity_label: SEVERITY_LABEL
      }
    end
  end
end
