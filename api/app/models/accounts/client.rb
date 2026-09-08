module Accounts
  class Client < ApplicationRecord
    belongs_to :firm
    has_many :tax_scenarios, class_name: "Scenario::TaxScenario", dependent: :destroy
    has_many :documents, class_name: "Ingestion::Document", dependent: :destroy
    has_many :audit_runs, class_name: "Audit::AuditRun", dependent: :destroy
    has_many :fiscal_files, class_name: "Ingestion::FiscalFile", dependent: :destroy
    validates :cnpj, presence: true, length: { is: 14 }, uniqueness: { scope: :firm_id }
    validates :legal_name, :uf, presence: true
  end
end
