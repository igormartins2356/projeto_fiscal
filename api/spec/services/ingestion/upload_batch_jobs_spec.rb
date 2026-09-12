require "rails_helper"

RSpec.describe "lote de upload: extração e parse" do
  before { seed_all! }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }
  let(:uploads) { Rails.root.join("storage", "uploads", "spec") }

  after { FileUtils.rm_rf(uploads) }

  def batch_for(filename, bytes)
    FileUtils.mkdir_p(uploads)
    ref = "spec/#{SecureRandom.hex(8)}"
    File.binwrite(Rails.root.join("storage", "uploads", ref), bytes)
    Ingestion::UploadBatch.create!(firm_id: client.firm_id, client:, original_filename: filename, storage_ref: ref)
  end

  def zip_with(entries)
    buffer = Zip::OutputStream.write_buffer(StringIO.new) do |z|
      entries.each { |name, content| z.put_next_entry(name); z.write(content) }
    end
    buffer.string
  end

  it "não deixa no storage do cliente o XML recusado, mas mantém o da nota importada" do
    storage = Ingestion::XmlStorage.new
    xml = nfe_fixture("sale_return_csosn_102")
    homologation = xml.gsub("<tpAmb>1</tpAmb>", "<tpAmb>2</tpAmb>")
    skipped_ref = storage.store(client:, hash: Digest::SHA256.hexdigest(homologation), xml: homologation)
    ok_ref = storage.store(client:, hash: Digest::SHA256.hexdigest(xml), xml:)
    batch = batch_for("lote.zip", "x")
    batch.update!(state: "parsing", files_total: 2)

    Ingestion::ParseDocumentJob.perform_now(batch.id, "homologacao.xml", skipped_ref)
    Ingestion::ParseDocumentJob.perform_now(batch.id, "nota.xml", ok_ref)
    expect(File.exist?(Rails.root.join("storage", "xml", skipped_ref))).to be(false)
    expect(File.exist?(Rails.root.join("storage", "xml", ok_ref))).to be(true)
  end

  it "marca o lote como failed quando o arquivo não é um zip legível" do
    batch = batch_for("corrompido.zip", "PK\x03\x04isto-nao-e-um-zip".b)
    expect { Ingestion::ExtractBatchJob.perform_now(batch.id) }.not_to raise_error
    expect(batch.reload.state).to eq("failed")
    expect(batch.errors_log.first["error"]).to be_present
  end

  it "enfileira a referência do XML no storage, não o XML inteiro" do
    xml = nfe_fixture("sale_return_csosn_102")
    batch = batch_for("lote.zip", zip_with("nota.xml" => xml))
    expect { Ingestion::ExtractBatchJob.perform_now(batch.id) }
      .to have_enqueued_job(Ingestion::ParseDocumentJob).with(batch.id, "lote.zip/nota.xml", a_string_matching(%r{\A#{client.id}/}))
    ref = ActiveJob::Base.queue_adapter.enqueued_jobs.last["arguments"].last
    expect(ref).not_to include("<nfeProc")
    expect(Ingestion::XmlStorage.new.read(ref)).to eq(xml)
    expect(batch.reload).to have_attributes(state: "parsing", files_total: 1)
  end

  it "não reenfileira um lote já distribuído (retry do Sidekiq)" do
    batch = batch_for("lote.zip", zip_with("nota.xml" => nfe_fixture("sale_return_csosn_102")))
    Ingestion::ExtractBatchJob.perform_now(batch.id)
    expect { Ingestion::ExtractBatchJob.perform_now(batch.id) }.not_to have_enqueued_job(Ingestion::ParseDocumentJob)
    expect(batch.reload.files_total).to eq(1)
  end

  # Um lote de centenas de XMLs não pode manter todo o conteúdo descompactado vivo no worker.
  def big_zip(count, marker)
    Zip::OutputStream.write_buffer(StringIO.new) do |z|
      count.times { |i| z.put_next_entry("nota#{i}.xml"); z.write("<nfeProc>#{marker}#{'x' * 800_000}#{i}</nfeProc>") }
    end.string
  end

  # sonda por prepend, não por stub do RSpec: o stub guarda os argumentos de cada chamada e seria ele
  # próprio a manter os XMLs vivos
  module StorePeakProbe
    class << self; attr_accessor :marker, :peak; end
    def store(**kwargs)
      if StorePeakProbe.marker
        GC.start
        alive = ObjectSpace.each_object(String).count { |x| x.bytesize > 500_000 && x.include?(StorePeakProbe.marker) }
        StorePeakProbe.peak = [StorePeakProbe.peak.to_i, alive].max
      end
      super
    end
  end

  it "grava cada entrada no storage durante a varredura, sem acumular o lote inteiro em memória" do
    Ingestion::XmlStorage.prepend(StorePeakProbe)
    batch = batch_for("lote.zip", big_zip(8, "PFVMARCADOR"))
    StorePeakProbe.marker, StorePeakProbe.peak = "PFVMARCADOR", 0
    begin
      Ingestion::ExtractBatchJob.perform_now(batch.id)
    ensure
      peak = StorePeakProbe.peak
      StorePeakProbe.marker = nil
    end
    expect(batch.reload).to have_attributes(state: "parsing", files_total: 8)
    expect(peak).to be <= 2
  end

  it "contabiliza XML pulado em files_skipped com o motivo, e fecha o lote" do
    storage = Ingestion::XmlStorage.new
    homologation = nfe_fixture("sale_return_csosn_102").gsub("<tpAmb>1</tpAmb>", "<tpAmb>2</tpAmb>")
    ref = storage.store(client:, hash: Digest::SHA256.hexdigest(homologation), xml: homologation)
    ok_ref = storage.store(client:, hash: Digest::SHA256.hexdigest(nfe_fixture("sale_return_csosn_102")), xml: nfe_fixture("sale_return_csosn_102"))
    batch = batch_for("lote.zip", "x")
    batch.update!(state: "parsing", files_total: 2)

    Ingestion::ParseDocumentJob.perform_now(batch.id, "homologacao.xml", ref)
    Ingestion::ParseDocumentJob.perform_now(batch.id, "nota.xml", ok_ref)
    batch.reload
    expect(batch).to have_attributes(files_parsed: 1, files_skipped: 1, files_failed: 0, state: "done")
    expect(batch.errors_log.first).to include("file" => "homologacao.xml")
    expect(batch.errors_log.first["skipped"]).to include("homologação")
  end
end
