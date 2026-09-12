require "rails_helper"

# [M20] prefixos de NCM, base legal e vigência de cada lei são dado (db/data), não Ruby.
RSpec.describe Catalog::Importers::PisCofinsSpecial do
  before do
    ncm = Catalog::ReferenceTable.create!(code: "ncm", name: "NCM", key_arity: 1, key_names: %w[ncm])
    v = ncm.versions.create!(version: 1, effective_from: Date.new(2020, 1, 1), state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!(%w[30049099 33051000 22021000 84713012].map { |code| { reference_version_id: v.id, key: [code], data: { "description" => code }, legal_basis: "TEC" } })
  end

  it "não guarda prefixos nem datas em Ruby" do
    expect(described_class.constants).not_to include(:GROUPS)
    expect(Catalog::Importers.constants).not_to include(:GROUPS)
    expect(File.read(Rails.root.join("app/services/catalog/importers/pis_cofins_special.rb"))).not_to match(/Date\.new\(\d{4}/)
  end

  it "expande os grupos do YAML com a vigência de cada lei" do
    result = described_class.new.call
    rows = result[:version].rows.index_by { |r| r.key.first }
    expect(rows.keys).to match_array(%w[30049099 33051000 22021000])
    expect(rows["30049099"].effective_from).to eq(Date.new(2001, 1, 1))
    expect(rows["30049099"].legal_basis).to include("Lei 10.147/2000")
    expect(rows["22021000"].effective_from).to eq(Date.new(2015, 1, 1))
    expect(result[:version].effective_from).to eq(Date.new(2001, 1, 1))
    expect(result[:version].rows.where(legal_basis: [nil, ""]).count).to eq(0)
  end
end
