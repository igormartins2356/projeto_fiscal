require "rails_helper"

RSpec.describe "Admin: rules & reference tables", type: :request do
  before { seed_all! }
  let(:h) { post "/api/v1/auth/login", params: { email: "admin@fiscal.local", password: "password123" }; { "Authorization" => "Bearer #{response.parsed_body['access_token']}" } }

  it "validates, tests and promotes a new rule version through the lifecycle" do
    post "/api/v1/admin/rules", params: { code: "ICMS.REGIME.SITUATION_FIELD" }, headers: h, as: :json
    expect(response).to have_http_status(:created), response.body
    rule = response.parsed_body
    expect(rule["version"]).to eq(2)
    expect(rule["state"]).to eq("draft")

    # regra inválida: caminho fora do escopo
    patch "/api/v1/admin/rules/#{rule['id']}", params: { body: rule["body"].merge("assert" => { "field" => "period.documents", "op" => "present" }) }, headers: h, as: :json
    post "/api/v1/admin/rules/#{rule['id']}/validate", headers: h
    expect(response.parsed_body["valid"]).to be false
    expect(response.parsed_body["errors"].first).to include("não está disponível no escopo item")
    post "/api/v1/admin/rules/#{rule['id']}/transition", params: { to: "testing" }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)

    patch "/api/v1/admin/rules/#{rule['id']}", params: { body: rule["body"] }, headers: h, as: :json
    post "/api/v1/admin/rules/#{rule['id']}/transition", params: { to: "testing" }, headers: h, as: :json
    expect(response.parsed_body["state"]).to eq("testing")

    # sombra exige casos de teste (1 dispara + 1 não dispara) passando
    post "/api/v1/admin/rules/#{rule['id']}/transition", params: { to: "shadow" }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    post "/api/v1/admin/rules/#{rule['id']}/test_cases", headers: h, as: :json, params: {
      name: "dispara", reference_date: "2026-03-14", scenario: { tax_regime: "lucro_presumido" }, input: { kind: "xml", fixture: "spec/fixtures/nfe/sale_return_csosn_102.xml" },
      expect: { findings: [{ item_number: 1, severity: "error", evidence: { "item.icms.situation_field" => "csosn" } }] } }
    expect(response).to have_http_status(:created), response.body
    post "/api/v1/admin/rules/#{rule['id']}/test_cases", headers: h, as: :json, params: {
      name: "não dispara (Simples com CSOSN)", reference_date: "2026-03-14", scenario: { tax_regime: "simples_nacional" },
      input: { kind: "xml", fixture: "spec/fixtures/nfe/sale_return_csosn_102.xml" }, expect: { findings: [] } }
    post "/api/v1/admin/rules/#{rule['id']}/test_cases/run_all", headers: h
    expect(response.parsed_body.map { |r| r["passed"] }).to eq([true, true])
    post "/api/v1/admin/rules/#{rule['id']}/transition", params: { to: "shadow" }, headers: h, as: :json
    expect(response.parsed_body["state"]).to eq("shadow")
    post "/api/v1/admin/rules/#{rule['id']}/transition", params: { to: "published" }, headers: h, as: :json
    expect(response.parsed_body["state"]).to eq("published")

    # a versão 2 passa a ser a escolhida pelo resolver
    client = Accounts::Client.find_by!(cnpj: "12345678000190")
    chosen = Rules::Resolver.new(client:, date: Date.new(2026, 3, 14)).call.find { |r| r.rule.code == "ICMS.REGIME.SITUATION_FIELD" }
    expect(chosen.rule.version).to eq(2)
  end

  it "imports a CSV into a draft version, diffs and publishes closing the previous one" do
    table = Catalog::ReferenceTable.find_by!(code: "icms_internal_rate")
    post "/api/v1/admin/reference_tables/#{table.id}/versions", params: { effective_from: "2026-04-01", copy_from_previous: true, notes: "AL 20,5%" }, headers: h, as: :json
    v = response.parsed_body
    expect(v["rows_count"]).to eq(4)
    csv = "uf;ncm;rate;fcp_rate;legal_basis\nAL;*;20.50;0.00;Lei AL 9.xxx/2025\nSP;*;18.00;0.00;RICMS/SP art. 52\n"
    file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "rates.csv")
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v['id']}/import", params: { file:, mode: "merge" }, headers: h
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["rows_count"]).to eq(5)
    get "/api/v1/admin/reference_tables/#{table.id}/versions/#{v['id']}/diff", headers: h
    expect(response.parsed_body["counts"]).to include("added" => 1, "changed" => 0)
    post "/api/v1/admin/reference_tables/#{table.id}/versions/#{v['id']}/publish", headers: h
    expect(response.parsed_body["state"]).to eq("published")
    expect(table.versions.find_by(version: 1).reload.effective_until).to eq(Date.new(2026, 3, 31))
    expect(Catalog::Lookup.new(date: Date.new(2026, 5, 1)).lookup("icms_internal_rate", %w[AL *])["rate"]).to eq("20.50")
    expect(Catalog::Lookup.new(date: Date.new(2026, 2, 1)).lookup("icms_internal_rate", %w[AL *])).to be_nil
  end

  it "lets a firm admin override a rule and a table row for a client, with precedence" do
    client = Accounts::Client.find_by!(cnpj: "12345678000190")
    post "/api/v1/rule_overrides", headers: h, as: :json, params: { rule_code: "ICMS.REGIME.SITUATION_FIELD", source_type: "client", source_id: client.id, override_action: "adjust",
      patch: { severity: "warning" }, effective_from: "2026-01-01", justification: "cliente possui consulta formal" }
    expect(response).to have_http_status(:created), response.body
    resolved = Rules::Resolver.new(client:, date: Date.new(2026, 3, 1)).call.find { |r| r.rule.code == "ICMS.REGIME.SITUATION_FIELD" }
    expect(resolved.definition["severity"]).to eq("warning")
    expect(resolved.source).to eq("client")

    table = Catalog::ReferenceTable.find_by!(code: "icms_internal_rate")
    post "/api/v1/reference_row_overrides", headers: h, as: :json, params: { reference_table_id: table.id, source_type: "client", source_id: client.id, key: %w[SP *],
      data: { rate: "12.00" }, effective_from: "2026-01-01", legal_basis: "Regime especial nº 1", justification: "regime especial" }
    expect(response).to have_http_status(:created), response.body
    expect(Catalog::Lookup.new(date: Date.new(2026, 3, 1), firm_id: client.firm_id, client_id: client.id).lookup("icms_internal_rate", %w[SP *])).to include("rate" => "12.00", "_source" => "client")
    expect(Catalog::Lookup.new(date: Date.new(2026, 3, 1)).lookup("icms_internal_rate", %w[SP *])["rate"]).to eq("18.00")
  end

  it "blocks non-admins from the admin namespace" do
    firm = Accounts::Firm.first
    Accounts::User.create!(firm:, name: "C", email: "c@x.com", password: "senha-forte-123", role: "accountant")
    post "/api/v1/auth/login", params: { email: "c@x.com", password: "senha-forte-123" }
    get "/api/v1/admin/rules", headers: { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
    expect(response).to have_http_status(:forbidden)
  end
end
