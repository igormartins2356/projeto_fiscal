require "rails_helper"

# Isolamento entre firmas (ARQUITETURA §9): tudo escopado por firm/client; recurso alheio responde 404 (nunca 403, que vaza existência).
RSpec.describe "Tenant isolation", type: :request do
  Tenant = Struct.new(:firm, :admin, :accountant, :client, :scenario, :run, :finding, :rule_override, :row_override, keyword_init: true)

  let!(:rule) do
    Rules::Rule.create!(code: "TEST.ISOLATION.RULE", version: 1, title: "t", scope: "item", severity: "error", state: "published", effective_from: Date.new(2020, 1, 1),
                        body: { "assert" => { "field" => "item.icms.cst", "op" => "present" }, "message" => "m" })
  end
  let!(:table) { Catalog::ReferenceTable.create!(code: "iso_table", name: "Tabela", key_arity: 1, key_names: ["uf"]) }
  let!(:a) { build_tenant("A", "11111111000111") }
  let!(:b) { build_tenant("B", "22222222000122") }

  def build_tenant(tag, cnpj)
    firm = Accounts::Firm.create!(name: "Firma #{tag}")
    admin = Accounts::User.create!(firm:, name: "Admin #{tag}", email: "admin#{tag.downcase}@x.com", password: "senha-forte-123", role: "firm_admin")
    accountant = Accounts::User.create!(firm:, name: "Conta #{tag}", email: "conta#{tag.downcase}@x.com", password: "senha-forte-123", role: "accountant")
    client = Accounts::Client.create!(firm:, cnpj:, legal_name: "Cliente #{tag}", uf: "SP")
    scenario = client.tax_scenarios.create!(effective_from: Date.new(2026, 1, 1), state: "draft", data: { "tax_regime" => "lucro_real" }, created_by: admin)
    run = client.audit_runs.create!(firm:, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31), state: "done")
    finding = run.findings.create!(client:, rule:, rule_code: rule.code, scope: "item", severity: "error", message: "x", dedupe_key: "#{rule.code}|#{tag}")
    rule_override = Rules::RuleOverride.create!(rule_code: rule.code, source_type: "client", source_id: client.id, override_action: "disable", effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
    row_override = Catalog::ReferenceRowOverride.create!(reference_table: table, source_type: "firm", source_id: firm.id, key: ["SP"], data: { "rate" => "12.00" }, effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
    Tenant.new(firm:, admin:, accountant:, client:, scenario:, run:, finding:, rule_override:, row_override:)
  end

  def login(user)
    post "/api/v1/auth/login", params: { email: user.email, password: "senha-forte-123" }
    response.parsed_body
  end

  def auth(user, client: nil)
    h = { "Authorization" => "Bearer #{login(user)['access_token']}" }
    h["X-Client-Id"] = client.id.to_s if client
    h
  end

  it "hides clients of another firm (show/update → 404)" do
    h = auth(a.admin)
    get "/api/v1/clients/#{b.client.id}", headers: h
    expect(response).to have_http_status(:not_found)
    patch "/api/v1/clients/#{b.client.id}", params: { legal_name: "Hack" }, headers: h, as: :json
    expect(response).to have_http_status(:not_found)
    expect(b.client.reload.legal_name).to eq("Cliente B")
  end

  it "rejects X-Client-Id of another firm (422) and finding of another firm (404)" do
    get "/api/v1/audit_runs", headers: auth(a.admin, client: b.client)
    expect(response).to have_http_status(:unprocessable_entity)
    patch "/api/v1/findings/#{b.finding.id}", params: { state: "fixed" }, headers: auth(a.admin, client: a.client), as: :json
    expect(response).to have_http_status(:not_found)
    expect(b.finding.reload.state).to eq("open")
  end

  it "returns 404 (not 403) for rule_overrides of another firm on update/destroy" do
    h = auth(a.admin)
    patch "/api/v1/rule_overrides/#{b.rule_override.id}", params: { justification: "hack" }, headers: h, as: :json
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/rule_overrides/#{b.rule_override.id}", headers: h
    expect(response).to have_http_status(:not_found)
    expect(Rules::RuleOverride.exists?(b.rule_override.id)).to be true
  end

  it "returns 404 (not 403) for reference_row_overrides of another firm on update/destroy" do
    h = auth(a.admin)
    patch "/api/v1/reference_row_overrides/#{b.row_override.id}", params: { justification: "hack" }, headers: h, as: :json
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/reference_row_overrides/#{b.row_override.id}", headers: h
    expect(response).to have_http_status(:not_found)
    expect(Catalog::ReferenceRowOverride.exists?(b.row_override.id)).to be true
  end

  it "refuses to create overrides pointing to a client of another firm" do
    h = auth(a.admin)
    post "/api/v1/rule_overrides", headers: h, as: :json, params: { rule_code: rule.code, source_type: "client", source_id: b.client.id, override_action: "disable", effective_from: "2026-01-01", justification: "j" }
    expect(response).to have_http_status(:unprocessable_entity)
    post "/api/v1/reference_row_overrides", headers: h, as: :json, params: { reference_table_id: table.id, source_type: "client", source_id: b.client.id, key: ["SP"], data: { rate: "1.00" }, effective_from: "2026-01-01", justification: "j" }
    expect(response).to have_http_status(:unprocessable_entity)
    post "/api/v1/rule_overrides", headers: h, as: :json, params: { rule_code: rule.code, source_type: "firm", source_id: b.firm.id, override_action: "disable", effective_from: "2026-01-01", justification: "j" }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "does not list overrides of another firm" do
    h = auth(a.admin)
    get "/api/v1/rule_overrides", headers: h
    expect(response.parsed_body.map { |o| o["id"] }).to eq([a.rule_override.id])
    get "/api/v1/reference_row_overrides", headers: h
    expect(response.parsed_body.map { |o| o["id"] }).to eq([a.row_override.id])
  end

  it "hides tax scenarios of a client of another firm" do
    h = auth(a.admin)
    get "/api/v1/clients/#{b.client.id}/tax_scenarios", headers: h
    expect(response).to have_http_status(:not_found)
    patch "/api/v1/clients/#{b.client.id}/tax_scenarios/#{b.scenario.id}", params: { data: { tax_regime: "simples_nacional" } }, headers: h, as: :json
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/clients/#{b.client.id}/tax_scenarios/#{b.scenario.id}", headers: h
    expect(response).to have_http_status(:not_found)
    expect(b.scenario.reload.data["tax_regime"]).to eq("lucro_real")
  end

  it "hides users of another firm from a firm_admin" do
    h = auth(a.admin)
    get "/api/v1/users", headers: h
    expect(response.parsed_body.map { |u| u["id"] }).to match_array([a.admin.id, a.accountant.id])
    patch "/api/v1/users/#{b.accountant.id}", params: { password: "novasenha1234" }, headers: h, as: :json
    expect(response).to have_http_status(:not_found)
    delete "/api/v1/users/#{b.accountant.id}", headers: h
    expect(response).to have_http_status(:not_found)
    expect(b.accountant.reload.active).to be true
  end

  it "rejects a firm_admin trying to grant platform_admin (422, no silent downgrade)" do
    h = auth(a.admin)
    post "/api/v1/users", params: { name: "X", email: "x@x.com", password: "senha-forte-123", role: "platform_admin" }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["error"]).to include("papel não permitido")
    expect(Accounts::User.find_by(email: "x@x.com")).to be_nil
    patch "/api/v1/users/#{a.accountant.id}", params: { role: "platform_admin" }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(a.accountant.reload.role).to eq("accountant")
  end

  it "logout_all invalidates refresh tokens" do
    body = login(a.admin)
    delete "/api/v1/auth/logout_all", headers: { "Authorization" => "Bearer #{body['access_token']}" }
    expect(response).to have_http_status(:no_content)
    post "/api/v1/auth/refresh", params: { refresh_token: body["refresh_token"] }
    expect(response).to have_http_status(:unauthorized)
  end

  it "change_password with wrong current password → 422; DELETE /auth/otp without code → 4xx" do
    h = auth(a.admin)
    post "/api/v1/users/change_password", params: { current_password: "errada-errada", password: "novasenha1234" }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(a.admin.reload.authenticate("senha-forte-123")).to be_truthy
    delete "/api/v1/auth/otp", params: { password: "senha-forte-123" }, headers: h, as: :json
    expect(response.status).to be_between(400, 499)
  end

  it "lets an accountant read reference table names but not the admin namespace" do
    h = auth(a.accountant)
    get "/api/v1/reference_tables", headers: h
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.map { |t| t["code"] }).to include("iso_table")
    get "/api/v1/admin/reference_tables/#{table.id}", headers: h
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/admin/reference_tables", headers: h
    expect(response).to have_http_status(:forbidden)
    get "/api/v1/reference_tables"
    expect(response).to have_http_status(:unauthorized)
  end
end
