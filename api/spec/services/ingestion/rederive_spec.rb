require "rails_helper"

RSpec.describe Ingestion::Rederive do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }
  let(:importer) { Ingestion::DocumentImporter.new(client:) }

  # a mesma venda a que a devolução da fixture se refere
  def original_xml
    nfe_fixture("sale_return_csosn_102")
      .gsub("35260312345678000190550010000012341000012345", "35260312345678000190550010000009991000009999")
      .sub(%r{<NFref>.*?</NFref>}m, "").sub("<nNF>1234</nNF>", "<nNF>999</nNF>")
  end

  it "mantém a referência resolvida depois de rederivar" do
    ret = importer.call(nfe_fixture("sale_return_csosn_102")).document
    original = importer.call(original_xml).document
    expect(ret.reload.data["references"].first).to include("resolved" => true, "document_id" => original.id)

    described_class.call(client.documents.fiscal)
    expect(ret.reload.data["references"].first).to include("resolved" => true, "document_id" => original.id)
  end

  it "reexecuta o ReferenceResolver: referência que apontava para documento excluído deixa de estar resolvida" do
    ret = importer.call(nfe_fixture("sale_return_csosn_102")).document
    original = importer.call(original_xml).document
    original.destroy
    described_class.call(client.documents.fiscal)
    expect(ret.reload.data["references"].first).to include("resolved" => false, "document_id" => nil)
  end

  it "corrige reference_date/period gravados com a data convertida para o fuso da aplicação" do
    doc = importer.call(nfe_fixture("sale_return_csosn_102").sub("2026-03-14T10:22:00-03:00", "2026-03-31T23:30:00-04:00")).document
    data = doc.data.merge("reference_date" => "2026-04-01", "period" => "2026-04")
    doc.update_columns(data:, reference_date: "2026-04-01", period: "2026-04")

    expect(described_class.call(client.documents.fiscal)).to eq(1)
    doc.reload
    expect(doc.reference_date.iso8601).to eq("2026-03-31")
    expect(doc.period).to eq("2026-03")
    expect(doc.data["reference_date"]).to eq("2026-03-31")
  end

  it "grava as versões do catálogo usadas" do
    doc = importer.call(nfe_fixture("sale_return_csosn_102")).document
    doc.update_columns(catalog_versions: {})
    described_class.call(client.documents.fiscal)
    expect(doc.reload.catalog_versions).to include("cfop", "csosn")
  end

  it "RederiveJob rederiva os documentos fiscais do cliente" do
    importer.call(nfe_fixture("sale_return_csosn_102"))
    expect(described_class).to receive(:call) { |scope| expect(scope.count).to eq(1) }
    Ingestion::RederiveJob.perform_now(client.id)
  end

  it "RederiveJob limita a rederivação ao período informado (documento de 2026-03 fora de uma tabela vigente em 2026-07)" do
    importer.call(nfe_fixture("sale_return_csosn_102"))
    expect(described_class).to receive(:call) { |scope| expect(scope.count).to eq(0) }
    Ingestion::RederiveJob.perform_now(client.id, period_start: Date.new(2026, 7, 1), period_end: nil)
  end

  it "RederiveJob sem client_id enfileira um job por cliente em vez de rederivar tudo de uma vez" do
    old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    expect(described_class).not_to receive(:call)
    expect { Ingestion::RederiveJob.perform_now(nil, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31)) }
      .to have_enqueued_job(Ingestion::RederiveJob).with(client.id, period_start: Date.new(2026, 3, 1), period_end: Date.new(2026, 3, 31))
  ensure
    ActiveJob::Base.queue_adapter = old_adapter
  end
end
