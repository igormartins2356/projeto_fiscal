require "rails_helper"

# [M17] linha de versão publicada é imutável fora do controller também (console, rake).
RSpec.describe Catalog::ReferenceRow do
  let(:table) { Catalog::ReferenceTable.create!(code: "ro_table", name: "Tabela", key_arity: 1, key_names: %w[ncm]) }
  let(:draft) { table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "draft") }

  it "permite escrever em versão draft" do
    row = draft.rows.create!(key: %w[84713012], data: { "description" => "x" }, legal_basis: "TEC")
    expect { row.update!(data: { "description" => "y" }) }.not_to raise_error
  end

  it "recusa criar ou alterar linha de versão publicada" do
    row = draft.rows.create!(key: %w[84713012], data: { "description" => "x" }, legal_basis: "TEC")
    draft.update!(state: "published", published_at: Time.current)
    expect { draft.rows.create!(key: %w[84713013], data: {}, legal_basis: "TEC") }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { row.reload.update!(data: { "description" => "y" }) }.to raise_error(ActiveRecord::ReadOnlyRecord)
  end
end
