require "rails_helper"

RSpec.describe Scenario::Validator do
  let(:base) { { "tax_regime" => "lucro_real", "uf" => "SP", "activity" => ["commerce"], "pis_cofins" => { "regime" => "non_cumulative" } } }

  it "aceita o cenário mínimo válido" do
    expect(described_class.new(base).errors).to eq([])
  end

  it "recusa atividade e regime de IBS/CBS fora da lista" do
    errors = described_class.new(base.merge("activity" => %w[banana], "ibs_cbs" => { "regime" => "xyz" })).errors
    expect(errors).to include(a_string_including("atividade inválida"), "regime de IBS/CBS inválido")
  end

  # exceção de ST sem base legal/vigência não pode virar dado do motor (DSL_RULES §7)
  it "exige NCM, aplicação, base legal e vigência na exceção de ST" do
    errors = described_class.new(base.merge("st" => { "overrides" => [{ "ncm" => "2202*" }] })).errors
    expect(errors).to include(a_string_including("informe se a ST se aplica"), a_string_including("informe a base legal"),
                              a_string_including("início de vigência inválido"))
  end

  it "aceita exceção de ST completa" do
    override = { "ncm" => "2202*", "applies" => false, "legal_basis" => "Convênio ICMS 142/18, cláusula 9ª", "effective_from" => "2026-01-01" }
    expect(described_class.new(base.merge("st" => { "source" => "catalog", "overrides" => [override] })).errors).to eq([])
  end

  it "exige tipo, base legal e vigência no benefício, e valida percentual/NCM" do
    errors = described_class.new(base.merge("benefits" => [{ "kind" => "desconto", "pct" => "150", "applies_to" => { "ncm" => ["abc"] } }])).errors
    expect(errors).to include(a_string_including("tipo inválido"), a_string_including("percentual inválido"),
                              a_string_including("NCM inválido em applies_to"), a_string_including("informe a base legal"))
  end

  it "aceita benefício completo e recusa fim de vigência anterior ao início" do
    benefit = { "kind" => "reduced_base", "pct" => "33.33", "applies_to" => { "ncm" => ["0402*"], "cfop" => ["5102"] },
                "legal_basis" => "Convênio ICMS 100/97", "effective_from" => "2026-01-01" }
    expect(described_class.new(base.merge("benefits" => [benefit])).errors).to eq([])
    errors = described_class.new(base.merge("benefits" => [benefit.merge("effective_until" => "2025-12-31")])).errors
    expect(errors).to include(a_string_including("fim da vigência deve ser posterior"))
  end
end
