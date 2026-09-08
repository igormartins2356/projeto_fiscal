class AddCoverageToAuditRuns < ActiveRecord::Migration[8.1]
  def change
    add_column :audit_runs, :coverage, :jsonb, null: false, default: {}   # lacunas de catálogo observadas no período (fila de curadoria)
  end
end
