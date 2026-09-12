require "rails_helper"
require "stringio"

# [M16] publicação fecha a vigência anterior mesmo com a mesma data e exige base legal em toda linha;
# [A14] o diff enxerga mudança de vigência; BAIXOS: retire/update auditados.
RSpec.describe "Admin: versões de tabela de referência", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Escritório") }
  let!(:admin) { Accounts::User.create!(firm:, name: "Ada", email: "ada@x.com", password: "senha-forte-123", role: "platform_admin") }
  let(:h) do
    post "/api/v1/auth/login", params: { email: "ada@x.com", password: "senha-forte-123" }
    { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
  end
  let(:table) { Catalog::ReferenceTable.create!(code: "adm_table", name: "Alíquota", key_arity: 2, key_names: %w[uf ncm]) }
  let!(:v1) do
    v = table.versions.create!(version: 1, effective_from: Date.new(2026, 1, 1), state: "published", published_at: Time.current)
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: v.id, key: %w[SP *], data: { "rate" => "18.00" }, legal_basis: "RICMS/SP art. 52" }])
    v
  end

  it "enfileira a rederivação dos clientes ao publicar (derivado do catálogo fica congelado na importação)" do
    old_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    client = Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "Cliente", uf: "SP", city_code: "3550308")
    v2 = draft_with(effective_from: Date.new(2026, 4, 1))
    expect { post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: h }
      .to have_enqueued_job(Ingestion::RederiveJob).with(nil, period_start: Date.new(2026, 4, 1), period_end: nil)
    expect(client).to be_present
    expect(response).to have_http_status(:ok)
  ensure
    ActiveJob::Base.queue_adapter = old_adapter
  end

  it "não colapsa no diff duas linhas da mesma chave com vigências diferentes" do
    v2 = table.versions.create!(version: 2, effective_from: Date.new(2026, 4, 1), state: "draft")
    Catalog::ReferenceRow.insert_all!([
      { reference_version_id: v2.id, key: %w[AL *], data: { "rate" => "19.00" }, effective_from: Date.new(2026, 4, 1), legal_basis: "Lei AL" },
      { reference_version_id: v2.id, key: %w[AL *], data: { "rate" => "20.50" }, effective_from: Date.new(2026, 5, 1), legal_basis: "Lei AL" }
    ])
    get "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/diff", headers: h
    expect(response.parsed_body["counts"]["added"]).to eq(2)
    expect(response.parsed_body["added"].map { |r| r["data"]["rate"] }).to match_array(%w[19.00 20.50])
  end

  def draft_with(effective_from:, legal_basis: "RICMS/SP art. 52", rate: "20.00")
    v = table.versions.create!(version: table.versions.maximum(:version) + 1, effective_from:, state: "draft")
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: v.id, key: %w[SP *], data: { "rate" => rate }, legal_basis: }])
    v
  end

  it "publicando com a mesma data de início, aposenta a anterior em vez de deixar duas vigentes" do
    v2 = draft_with(effective_from: Date.new(2026, 1, 1))
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: h
    expect(response).to have_http_status(:ok), response.body
    expect(v1.reload.state).to eq("retired")
    expect(table.versions.published.effective_on(Date.new(2026, 3, 1)).count).to eq(1)
    expect(Catalog::Lookup.new(date: Date.new(2026, 3, 1)).lookup("adm_table", %w[SP *])["rate"]).to eq("20.00")
  end

  it "publicando com data posterior, fecha a anterior na véspera e mantém a consulta histórica" do
    v2 = draft_with(effective_from: Date.new(2026, 4, 1))
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: h
    expect(v1.reload.effective_until).to eq(Date.new(2026, 3, 31))
    expect(v1.state).to eq("published")
    expect(Catalog::Lookup.new(date: Date.new(2026, 2, 1)).lookup("adm_table", %w[SP *])["rate"]).to eq("18.00")
    expect(Catalog::Lookup.new(date: Date.new(2026, 5, 1)).lookup("adm_table", %w[SP *])["rate"]).to eq("20.00")
  end

  it "recusa publicar versão com linha sem base legal" do
    v2 = draft_with(effective_from: Date.new(2026, 4, 1), legal_basis: nil)
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/publish", headers: h
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("sem base legal")
    expect(v2.reload.state).to eq("draft")
  end

  it "mostra no diff a linha que só teve a vigência encerrada (A14)" do
    v2 = table.versions.create!(version: 2, effective_from: Date.new(2026, 4, 1), state: "draft")
    Catalog::ReferenceRow.insert_all!([{ reference_version_id: v2.id, key: %w[SP *], data: { "rate" => "18.00" }, effective_until: Date.new(2026, 3, 31), legal_basis: "RICMS/SP art. 52" }])
    get "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/diff", headers: h
    expect(response.parsed_body["counts"]).to include("changed" => 1, "unchanged" => 0)
    expect(response.parsed_body["changed"].first["after"]["effective_until"]).to eq("2026-03-31")
  end

  it "devolve 422 pt-BR para arquivo inválido, sem tocar na versão" do
    v2 = table.versions.create!(version: 2, effective_from: Date.new(2026, 4, 1), state: "draft")
    file = Rack::Test::UploadedFile.new(StringIO.new("uf;rate\nSP;18.00\n"), "text/csv", original_filename: "r.csv")
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/import", params: { file: }, headers: h
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("CSV sem coluna(s) de chave: ncm")
  end

  it "audita a edição e a aposentadoria da versão" do
    v2 = draft_with(effective_from: Date.new(2026, 4, 1))
    patch "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}", params: { notes: "AL 20,5%" }, headers: h, as: :json
    expect(response).to have_http_status(:ok)
    expect(Audit::AuditLog.where(action: "reference_version_updated", subject_id: v2.id).count).to eq(1)
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v2.id}/retire", headers: h
    expect(Audit::AuditLog.where(action: "reference_version_retired", subject_id: v2.id).count).to eq(1)
  end
end
