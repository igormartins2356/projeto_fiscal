require "rails_helper"

RSpec.describe Audit::TemporalPartition do
  let(:firm) { Accounts::Firm.create!(name: "Escritório Partição", cnpj: "11222333000181") }
  let(:client) { Accounts::Client.create!(firm:, cnpj: "11222333000182", legal_name: "Cliente Partição", uf: "SP") }
  let(:table) { Catalog::ReferenceTable.create!(code: "tabela_particao", name: "Tabela partição", key_arity: 1, key_names: %w[chave]) }

  def partition = described_class.call(client:, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))

  it "não corta o período por linha de versão em rascunho" do
    draft = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "draft")
    Catalog::ReferenceRow.create!(reference_version: draft, key: %w[X], data: { "rate" => "18.00" }, effective_from: Date.new(2026, 3, 15))
    expect(partition.map { |i| [i.from, i.to] }).to eq([[Date.new(2026, 3, 1), Date.new(2026, 3, 31)]])
  end

  it "continua cortando o período por linha de versão publicada" do
    published = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: published.id, key: %w[X], data: { "rate" => "18.00" }, effective_from: Date.new(2026, 3, 15) }])
    expect(partition.map { |i| [i.from, i.to] })
      .to eq([[Date.new(2026, 3, 1), Date.new(2026, 3, 14)], [Date.new(2026, 3, 15), Date.new(2026, 3, 31)]])
  end
end
