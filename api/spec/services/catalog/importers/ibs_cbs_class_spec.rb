require "rails_helper"

# [M16] toda linha publicada precisa de base legal; [M20] a data de início do regime é constante citada.
RSpec.describe Catalog::Importers::IbsCbsClass do
  it "preenche legal_basis no formato plano" do
    row = described_class.new.send(:parse_flat, [{ "cClassTrib" => "1", "CST" => "0", "Descricao" => "Tributação integral" }]).first
    expect(row[:legal_basis]).to eq("LC 214/2025")
    expect(row[:data]["legal_basis"]).to eq("LC 214/2025")
    expect(row[:key]).to eq(["000001"])
  end

  it "usa a legislação da fonte quando ela vem preenchida" do
    row = described_class.new.send(:parse_flat, [{ "cClassTrib" => "200003", "CST" => "200", "TexUrlLegislacao" => "LC 214/2025, art. 130" }]).first
    expect(row[:legal_basis]).to eq("LC 214/2025, art. 130")
  end

  it "nomeia a data de início do regime em vez de literal" do
    expect(described_class::LC_214_EFFECTIVE_FROM).to eq(Date.new(2026, 1, 1))
    expect(File.read(Rails.root.join("app/services/catalog/importers/ibs_cbs_class.rb"))).not_to match(/Date\.new\(2026, 1, 1\)\]/)
  end
end
