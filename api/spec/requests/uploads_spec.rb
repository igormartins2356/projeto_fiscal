require "rails_helper"

RSpec.describe "Uploads (XML batches, EFD files, listings)", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let(:h) do
    post "/api/v1/auth/login", params: { email: "ana@x.com", password: "senha-forte-123" }
    { "Authorization" => "Bearer #{response.parsed_body['access_token']}", "X-Client-Id" => client.id.to_s }
  end

  def upload(content, name, type = "application/octet-stream") = Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)

  after { FileUtils.rm_rf(Rails.root.join("storage", "uploads", client.id.to_s)) }

  describe "POST /uploads" do
    it "rejects a non-file param with 422 instead of 500" do
      post "/api/v1/uploads", params: { file: "string" }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("arquivo inválido")
      expect(Ingestion::UploadBatch.count).to eq(0)
    end

    it "rejects extensions outside the allow-list (.zip/.xml)" do
      post "/api/v1/uploads", params: { file: upload("MZ", "notas.exe") }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("extensão")
      expect(Ingestion::UploadBatch.count).to eq(0)
    end

    it "rejects files above MAX_UPLOAD_BYTES" do
      stub_const("Api::V1::UploadsController::MAX_UPLOAD_BYTES", 10)
      post "/api/v1/uploads", params: { file: upload("x" * 11, "notas.zip") }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("tamanho")
    end

    it "accepts a .ZIP (case-insensitive), records the author, audits and hides storage_ref" do
      post "/api/v1/uploads", params: { file: upload("PK\x03\x04", "Notas Julho.ZIP") }, headers: h
      expect(response).to have_http_status(:created), response.body
      body = response.parsed_body
      expect(body.keys).to match_array(%w[id state original_filename files_total files_parsed files_failed files_skipped errors_log created_at])
      batch = Ingestion::UploadBatch.find(body["id"])
      expect(batch.user).to eq(user)
      expect(batch.original_filename).to eq("Notas Julho.ZIP")
      expect(Audit::AuditLog.where(action: "upload_created", user:, subject_id: batch.id).count).to eq(1)
      get "/api/v1/uploads/#{batch.id}", headers: h
      expect(response.parsed_body).not_to have_key("storage_ref")
    end

    it "sanitizes original_filename (null bytes / path)" do
      allow_any_instance_of(ActionDispatch::Http::UploadedFile).to receive(:original_filename).and_return("../evil\0.xml")
      post "/api/v1/uploads", params: { file: upload("<xml/>", "a.xml") }, headers: h
      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body["original_filename"]).to eq("evil.xml")
    end
  end

  describe "POST /fiscal_files" do
    it "rejects a non-file param with 422" do
      post "/api/v1/fiscal_files", params: { file: "string" }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("arquivo inválido")
    end

    it "rejects extensions other than .txt" do
      post "/api/v1/fiscal_files", params: { file: upload("|0000|", "efd.xml") }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("extensão")
    end

    it "rejects files above MAX_UPLOAD_BYTES" do
      stub_const("Api::V1::FiscalFilesController::MAX_UPLOAD_BYTES", 10)
      post "/api/v1/fiscal_files", params: { file: upload("|0000|" * 5, "efd.txt") }, headers: h
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("tamanho")
    end

    it "accepts a .TXT and audits" do
      expect { post "/api/v1/fiscal_files", params: { file: upload("|0000|017|0|", "EFD.TXT") }, headers: h }
        .to have_enqueued_job(Ingestion::ParseFiscalFileJob)
      expect(response).to have_http_status(:accepted)
      expect(Audit::AuditLog.where(action: "fiscal_file_uploaded", user:).count).to eq(1)
    end
  end

  describe "paginated listings" do
    it "GET /audit_runs returns {data,total,page,per_page} ordered by created_at desc" do
      runs = 3.times.map { |i| client.audit_runs.create!(firm:, period_start: Date.new(2026, 1, 1), period_end: Date.new(2026, 1, 31), created_at: Time.current - (3 - i).hours) }
      get "/api/v1/audit_runs", params: { per_page: 2 }, headers: h
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("total" => 3, "page" => 1, "per_page" => 2)
      expect(body["data"].map { |r| r["id"] }).to eq([runs[2].id, runs[1].id])
      get "/api/v1/audit_runs", params: { per_page: 2, page: 2 }, headers: h
      expect(response.parsed_body["data"].map { |r| r["id"] }).to eq([runs[0].id])
    end

    it "GET /fiscal_files returns {data,total,page,per_page} ordered by created_at desc" do
      files = 3.times.map { |i| client.fiscal_files.create!(firm:, kind: "sped_icms_ipi", file_hash: "h#{i}", storage_ref: "r#{i}", created_at: Time.current - (3 - i).hours) }
      get "/api/v1/fiscal_files", params: { per_page: 2 }, headers: h
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body).to include("total" => 3, "page" => 1, "per_page" => 2)
      expect(body["data"].map { |f| f["id"] }).to eq([files[2].id, files[1].id])
      expect(body["data"].first.keys).to include("summary", "errors_count")
    end
  end
end
