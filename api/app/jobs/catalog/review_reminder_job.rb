module Catalog
  # Marca no audit_log as tabelas com revisão vencida (next_review_on) — o painel de tabelas já as destaca em vermelho.
  class ReviewReminderJob < ApplicationJob
    queue_as :catalog

    def perform
      overdue = Catalog::ReferenceTable.where("next_review_on <= ?", Date.current).pluck(:code)
      missing = Catalog::ReferenceTable.all.reject { |t| t.version_effective_on(Date.current) }.map(&:code)
      return if overdue.empty? && missing.empty?
      Audit::AuditLog.record!("catalog_review_due", metadata: { overdue:, missing: })
    end
  end
end
