require "rails_helper"

# Validações de domínio dos modelos que o banco não expressa (state/enum e coerência de período/vigência).
RSpec.describe "validações de domínio" do
  let(:firm) { Accounts::Firm.create!(name: "Escritório Teste", cnpj: "11111111000111") }
  let(:other_firm) { Accounts::Firm.create!(name: "Outro Escritório", cnpj: "22222222000122") }
  let(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "Cliente Teste Ltda", uf: "SP") }

  describe Audit::AuditRun do
    it "recusa período invertido" do
      run = client.audit_runs.new(firm_id: firm.id, period_start: Date.new(2026, 3, 31), period_end: Date.new(2026, 3, 1))
      expect(run).not_to be_valid
      expect(run.errors[:period_end]).to include("deve ser igual ou posterior ao início do período")
    end

    it "recusa firma diferente da firma do cliente" do
      run = client.audit_runs.new(firm_id: other_firm.id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
      expect(run).not_to be_valid
      expect(run.errors[:firm_id]).to include("não é a firma do cliente")
    end

    it "recusa estado fora do ciclo de vida" do
      run = client.audit_runs.new(firm_id: firm.id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31), state: "concluido")
      expect(run).not_to be_valid
    end
  end

  describe Catalog::ReferenceVersion do
    let(:table) { Catalog::ReferenceTable.create!(code: "tabela_teste", name: "Tabela de teste", key_names: %w[uf], key_arity: 1) }

    it "recusa vigência que termina antes de começar" do
      version = table.versions.new(version: 1, effective_from: Date.new(2026, 3, 31), effective_until: Date.new(2026, 3, 1), state: "draft")
      expect(version).not_to be_valid
      expect(version.errors[:effective_until]).to include("deve ser igual ou posterior ao início da vigência")
    end

    it "recusa estado fora do ciclo de vida" do
      expect(table.versions.new(version: 1, effective_from: Date.new(2026, 1, 1), state: "publicada")).not_to be_valid
    end
  end

  describe Ingestion::Document do
    it "recusa kind e status_state desconhecidos" do
      doc = Ingestion::Document.new(firm:, client:, kind: "nfse", xml_hash: "a" * 64, xml_ref: "x", status_state: "autorizada")
      expect(doc).not_to be_valid
      expect(doc.errors.attribute_names).to include(:kind, :status_state)
    end
  end

  describe Ingestion::FiscalFile do
    it "recusa kind e state desconhecidos" do
      file = Ingestion::FiscalFile.new(firm:, client:, kind: "sped_contribuicoes", file_hash: "b" * 64, storage_ref: "x", state: "processando")
      expect(file).not_to be_valid
      expect(file.errors.attribute_names).to include(:kind, :state)
    end
  end

  describe Ingestion::UploadBatch do
    it "recusa state desconhecido" do
      expect(Ingestion::UploadBatch.new(firm:, client:, state: "processando")).not_to be_valid
    end
  end
end
