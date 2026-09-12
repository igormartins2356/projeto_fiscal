require "rails_helper"

RSpec.describe Ingestion::DocumentImporter do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }
  subject(:importer) { described_class.new(client:) }

  it "importa carta de correção e cancelamento da mesma nota e projeta o cancelamento" do
    note = importer.call(nfe_fixture("sale_return_csosn_102")).document
    expect(importer.call(nfe_fixture("event_110110_correction")).status).to eq(:created)
    expect(importer.call(nfe_fixture("event_110111_cancellation")).status).to eq(:created)
    expect(client.documents.where(kind: "event").count).to eq(2)
    expect(note.reload.status_state).to eq("cancelled")
  end

  # O mesmo evento reenviado com outra formatação tem xml_hash diferente: sem procurá-lo pela
  # identidade do evento, o índice único vira falha crua do Postgres no lote do contador.
  it "trata o mesmo evento reenviado com formatação diferente como duplicata, não como falha" do
    importer.call(nfe_fixture("sale_return_csosn_102"))
    first = importer.call(nfe_fixture("event_110111_cancellation"))
    again = importer.call(nfe_fixture("event_110111_cancellation").sub("<infEvento", "<infEvento "))
    expect(again.status).to eq(:duplicate)
    expect(again.document).to eq(first.document)
    expect(client.documents.where(kind: "event").count).to eq(1)
  end

  it "grava as versões do catálogo usadas na derivação" do
    doc = importer.call(nfe_fixture("sale_return_csosn_102")).document
    expect(doc.catalog_versions).to include("csosn", "cfop")
    expect(doc.catalog_versions["cfop"]).to eq(Catalog::ReferenceTable.find_by!(code: "cfop").version_effective_on(doc.reference_date).id)
  end

  it "pula XML de homologação, de terceiro e sem tpAmb, com motivo em pt-BR" do
    homologation = importer.call(nfe_fixture("sale_return_csosn_102").gsub("<tpAmb>1</tpAmb>", "<tpAmb>2</tpAmb>"))
    expect(homologation.status).to eq(:skipped)
    expect(homologation.reason).to include("homologação")

    third_party = importer.call(nfe_fixture("sale_return_csosn_102").gsub("12345678000190", "11111111000191"))
    expect(third_party.status).to eq(:skipped)
    expect(third_party.reason).to include("terceiro")

    no_env = importer.call(nfe_fixture("sale_return_csosn_102").gsub("<tpAmb>1</tpAmb>", ""))
    expect(no_env.status).to eq(:skipped)
    expect(no_env.reason).to include("tpAmb")
    expect(client.documents.count).to eq(0)
  end
end
