require "rails_helper"

RSpec.describe Accounts::Client do
  let(:firm) { Accounts::Firm.create!(name: "Escritório Teste", cnpj: "11111111000111") }
  let(:user) { Accounts::User.create!(firm:, name: "Contador", email: "contador@teste.local", password: "password123", role: "firm_admin") }
  let(:client) { described_class.create!(firm:, cnpj: "12345678000190", legal_name: "Cliente Teste Ltda", uf: "SP") }

  # Exclusão a pedido do titular (ARQUITETURA §9 / LGPD): tem de apagar o cliente inteiro sem violar FK.
  def build_full_graph!
    rule = Rules::Rule.create!(code: "TEST.DESTROY", version: 1, title: "Regra de teste", scope: "item", severity: "error",
                              state: "published", effective_from: Date.new(2026, 1, 1), source_type: "platform", body: {})
    batch = Ingestion::UploadBatch.create!(firm:, client:, user:, state: "done", original_filename: "notas.zip")
    document = Ingestion::Document.create!(firm:, client:, upload_batch: batch, kind: "nfe", model: "55",
                                           access_key: "3" * 44, xml_hash: "a" * 64, xml_ref: "spec/a.xml", role: "issuer",
                                           reference_date: Date.new(2026, 3, 10), status_state: "authorized", data: {})
    document.items.create!(client_id: client.id, number: 1, data: {})
    fiscal_file = Ingestion::FiscalFile.create!(firm:, client:, upload_batch: batch, kind: "sped_icms_ipi",
                                               file_hash: "b" * 64, storage_ref: "spec/sped.txt", state: "done")
    parent = fiscal_file.records.create!(line_number: 1, record_type: "C100", block: "C", document_id: document.id, fields: {})
    record = fiscal_file.records.create!(line_number: 2, record_type: "C170", block: "C", parent_id: parent.id, fields: {})
    run = client.audit_runs.create!(firm_id: firm.id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
    Audit::Finding.create!(audit_run: run, client:, rule:, rule_code: rule.code, document:, item_number: 1,
                           scope: "item", severity: "error", message: "apontamento", dedupe_key: "k1")
    Audit::Finding.create!(audit_run: run, client:, rule:, rule_code: rule.code, fiscal_record_id: record.id,
                           scope: "period", severity: "warning", message: "apontamento sped", dedupe_key: "k2")
    Scenario::TaxScenario.create!(client:, effective_from: Date.new(2026, 1, 1), state: "published", data: {})
  end

  it "apaga todo o grafo do cliente sem violar chave estrangeira" do
    build_full_graph!
    expect { client.destroy! }.not_to raise_error
    expect(Audit::Finding.where(client_id: client.id).count).to eq(0)
    expect(Ingestion::Document.where(client_id: client.id).count).to eq(0)
    expect(Ingestion::DocumentItem.where(client_id: client.id).count).to eq(0)
    expect(Ingestion::FiscalFile.where(client_id: client.id).count).to eq(0)
    expect(Ingestion::FiscalRecord.count).to eq(0)
    expect(Ingestion::UploadBatch.where(client_id: client.id).count).to eq(0)
    expect(Audit::AuditRun.where(client_id: client.id).count).to eq(0)
    expect(Scenario::TaxScenario.where(client_id: client.id).count).to eq(0)
  end
end
