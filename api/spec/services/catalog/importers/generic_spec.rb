require "rails_helper"
require "stringio"

# [M17] só versão draft recebe linhas; [M19] encoding, decimal com vírgula, row_schema e chave duplicada.
RSpec.describe Catalog::Importers::Generic do
  let(:table) { Catalog::ReferenceTable.create!(code: "gen_table", name: "Tabela", key_arity: 2, key_names: %w[uf ncm]) }
  let(:version) { table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "draft") }

  def upload(content, name = "linhas.csv")
    Rack::Test::UploadedFile.new(StringIO.new(content), "text/csv", original_filename: name)
  end

  it "importa CSV em ISO-8859-1 sem quebrar" do
    csv = "uf;ncm;rate;legal_basis\nSP;*;18.00;Decreto de São Paulo nº 1\n".encode("ISO-8859-1")
    described_class.new(table, version).call(file: upload(csv))
    expect(version.rows.reload.first.legal_basis).to eq("Decreto de São Paulo nº 1")
  end

  it "grava decimal com vírgula em ponto" do
    described_class.new(table, version).call(file: upload("uf;ncm;rate;fcp_rate;legal_basis\nSP;*;18,00;1.234,56;RICMS\n"))
    expect(version.rows.reload.first.data).to eq("rate" => "18.00", "fcp_rate" => "1234.56")
  end

  it "recusa chave repetida no arquivo" do
    expect { described_class.new(table, version).call(file: upload("uf;ncm;rate;legal_basis\nSP;*;18.00;a\nSP;*;17.00;b\n")) }
      .to raise_error(described_class::InvalidData, /repetida/)
    expect(version.rows.count).to eq(0)
  end

  it "valida o row_schema da tabela" do
    table.update!(row_schema: { "rate" => { "type" => "decimal", "required" => true }, "st" => "boolean" })
    expect { described_class.new(table, version).call(file: upload("uf;ncm;rate;st;legal_basis\nSP;*;dezoito;true;a\n")) }
      .to raise_error(described_class::InvalidData, /não é decimal válido/)
    expect { described_class.new(table, version).call(file: upload("uf;ncm;rate;st;legal_basis\nSP;*;;true;a\n")) }
      .to raise_error(described_class::InvalidData, /obrigatória/)
    described_class.new(table, version).call(file: upload("uf;ncm;rate;st;legal_basis\nSP;*;18,00;sim;a\n"))
    expect(version.rows.reload.first.data).to eq("rate" => "18.00", "st" => true)
  end

  it "recusa escrever em versão publicada" do
    described_class.new(table, version).call(rows: [{ key: %w[SP *], data: { "rate" => "18.00" }, legal_basis: "RICMS" }])
    version.update!(state: "published", published_at: Time.current)
    expect { described_class.new(table, version).call(rows: [{ key: %w[MG *], data: { "rate" => "18.00" } }], mode: "merge") }
      .to raise_error(described_class::InvalidData, /draft/)
    expect(version.rows.count).to eq(1)
  end
end
