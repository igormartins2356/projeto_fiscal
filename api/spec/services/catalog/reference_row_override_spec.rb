require "rails_helper"

# [M15] vigência da sobreposição é dado: início obrigatório, fim >= início, sem sobreposição para a mesma chave.
RSpec.describe Catalog::ReferenceRowOverride do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let(:table) { Catalog::ReferenceTable.create!(code: "ov_val", name: "Tabela", key_arity: 2, key_names: %w[uf ncm]) }
  let(:base) { { reference_table: table, source_type: "firm", source_id: firm.id, key: %w[SP *], data: { "rate" => "12.00" }, justification: "regime especial", created_by: user } }

  it "exige effective_from" do
    o = described_class.new(base)
    expect(o).not_to be_valid
    expect(o.errors[:effective_from]).to include("não pode ficar em branco")
  end

  it "recusa fim de vigência anterior ao início" do
    o = described_class.new(base.merge(effective_from: Date.new(2026, 6, 1), effective_until: Date.new(2026, 1, 1)))
    expect(o).not_to be_valid
    expect(o.errors[:effective_until].join).to include("posterior ao início")
  end

  it "recusa vigência sobreposta na mesma tabela/origem/chave" do
    described_class.create!(base.merge(effective_from: Date.new(2026, 1, 1)))
    o = described_class.new(base.merge(effective_from: Date.new(2026, 2, 1), data: { "rate" => "20.00" }))
    expect(o).not_to be_valid
    expect(o.errors[:effective_from].join).to include("sobrepõe")
  end

  it "aceita a nova quando a anterior foi encerrada, e aceita outra chave/origem" do
    first = described_class.create!(base.merge(effective_from: Date.new(2026, 1, 1)))
    first.update!(effective_until: Date.new(2026, 1, 31))
    expect(described_class.new(base.merge(effective_from: Date.new(2026, 2, 1)))).to be_valid
    expect(described_class.new(base.merge(effective_from: Date.new(2026, 1, 1), key: %w[MG *]))).to be_valid
  end

  it "não acusa sobreposição contra si mesma ao editar" do
    o = described_class.create!(base.merge(effective_from: Date.new(2026, 1, 1)))
    expect { o.update!(data: { "rate" => "13.00" }) }.not_to raise_error
  end
end
