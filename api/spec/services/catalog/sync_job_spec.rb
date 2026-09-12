require "rails_helper"

# [A14] vigência/base legal da linha entram na comparação; [M26] draft idêntico não é recriado todo dia.
RSpec.describe Catalog::SyncJob do
  let!(:table) { Catalog::ReferenceTable.create!(code: "ncm", name: "NCM", key_arity: 1, key_names: %w[ncm]) }
  let!(:published) do
    v = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: v.id, key: %w[84713012], data: { "description" => "Máquinas portáteis" }, effective_from: Date.new(2022, 4, 1), legal_basis: "Resolução GECEX 272/2021" }])
    v
  end
  let(:importer) do
    Class.new do
      class << self; attr_accessor :rows; end
      def initialize(table) = @table = table
      def call(**)
        last = @table.versions.order(version: :desc).first
        version = @table.versions.create!(version: (last&.version || 0) + 1, effective_from: Date.new(2026, 1, 1), state: "draft")
        Catalog::ReferenceRow.insert_all!(self.class.rows.map { |r| r.merge(reference_version_id: version.id) })
        { version:, imported: self.class.rows.size }
      end
    end
  end
  let(:current_rows) { published.rows.map { |r| { key: r.key, data: r.data, effective_from: r.effective_from, effective_until: r.effective_until, legal_basis: r.legal_basis } } }

  before { stub_const("Catalog::SyncJob::IMPORTERS", { "ncm" => importer }) }

  def last_action = Audit::AuditLog.order(:id).last.action

  it "descarta o draft quando nada mudou nos cinco campos" do
    importer.rows = current_rows
    described_class.perform_now("ncm")
    expect(table.versions.where(state: "draft").count).to eq(0)
    expect(last_action).to eq("catalog_sync_unchanged")
  end

  it "cria draft quando só a vigência da linha muda (A14)" do
    importer.rows = current_rows.map { |r| r.merge(effective_until: Date.new(2026, 12, 31)) }
    described_class.perform_now("ncm")
    expect(table.versions.where(state: "draft").count).to eq(1)
    expect(last_action).to eq("catalog_sync_new_draft")
  end

  it "cria draft quando só a base legal da linha muda (A14)" do
    importer.rows = current_rows.map { |r| r.merge(legal_basis: "Resolução GECEX 999/2026") }
    described_class.perform_now("ncm")
    expect(table.versions.where(state: "draft").count).to eq(1)
  end

  # Mesma chave com vigências diferentes é legítima dentro de uma versão (ARQUITETURA §13): a alíquota/descrição
  # muda no meio da vigência da tabela. Indexar o fingerprint só por `key` guardava uma linha só.
  context "quando a mesma chave tem duas vigências na versão" do
    let!(:second_vigencia) do
      Catalog::ReferenceRow.insert_all!([{ reference_version_id: published.id, key: %w[84713012], data: { "description" => "Máquinas portáteis (2026)" },
                                           effective_from: Date.new(2026, 1, 1), legal_basis: "Resolução GECEX 500/2025" }])
    end

    it "cria draft quando muda o dado da vigência antiga" do
      importer.rows = current_rows.map { |r| r[:effective_from] == Date.new(2022, 4, 1) ? r.merge(data: { "description" => "Máquinas portáteis (retificado)" }) : r }
      described_class.perform_now("ncm")
      expect(table.versions.where(state: "draft").count).to eq(1)
      expect(last_action).to eq("catalog_sync_new_draft")
    end

    it "descarta o draft quando nenhuma das vigências mudou" do
      importer.rows = current_rows
      described_class.perform_now("ncm")
      expect(table.versions.where(state: "draft").count).to eq(0)
      expect(last_action).to eq("catalog_sync_unchanged")
    end
  end

  it "não recria o mesmo draft no dia seguinte (M26)" do
    importer.rows = current_rows.map { |r| r.merge(effective_until: Date.new(2026, 12, 31)) }
    described_class.perform_now("ncm")
    described_class.perform_now("ncm")
    expect(table.versions.where(state: "draft").count).to eq(1)
    expect(last_action).to eq("catalog_sync_unchanged")
    expect(Audit::AuditLog.order(:id).last.metadata.dig("metadata", "same_as")).to eq("draft")
  end
end
