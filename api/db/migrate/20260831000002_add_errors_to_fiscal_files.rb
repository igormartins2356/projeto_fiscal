class AddErrorsToFiscalFiles < ActiveRecord::Migration[8.1]
  def change
    add_column :fiscal_files, :errors_log, :jsonb, null: false, default: []
    add_column :fiscal_files, :summary, :jsonb, null: false, default: {}   # contagens por registro, totais
    add_reference :fiscal_files, :uploaded_by, foreign_key: { to_table: :users }
  end
end
