require "rails_helper"

# Situação do apontamento (ARQUITETURA §13.2): quem mudou, quando e por quê ficam registrados.
RSpec.describe "Findings, scenarios and admin auditing", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:admin) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let!(:platform) { Accounts::User.create!(firm:, name: "Root", email: "root@x.com", password: "senha-forte-123", role: "platform_admin") }
  let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let!(:rule) do
    Rules::Rule.create!(code: "TEST.FINDING.RULE", version: 1, title: "t", scope: "item", severity: "error", state: "published", effective_from: Date.new(2020, 1, 1),
                        body: { "assert" => { "field" => "item.icms.cst", "op" => "present" }, "message" => "m" })
  end
  let!(:run) { client.audit_runs.create!(firm:, period_start: Date.new(2026, 7, 1), period_end: Date.new(2026, 7, 31), state: "done") }
  let!(:finding) { run.findings.create!(client:, rule:, rule_code: rule.code, scope: "item", severity: "error", message: "x", dedupe_key: "k1") }

  def auth(user, with_client: false)
    post "/api/v1/auth/login", params: { email: user.email, password: "senha-forte-123" }
    h = { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
    h["X-Client-Id"] = client.id.to_s if with_client
    h
  end

  describe "PATCH /findings/:id" do
    it "requires a justification for justified/false_positive/ignored" do
      patch "/api/v1/findings/#{finding.id}", params: { state: "justified" }, headers: auth(admin, with_client: true), as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("justificativa obrigatória")
      expect(finding.reload.state).to eq("open")
    end

    it "records who changed the state, when, and writes an audit log" do
      patch "/api/v1/findings/#{finding.id}", params: { state: "false_positive", state_note: "operação isenta por convênio" }, headers: auth(admin, with_client: true), as: :json
      expect(response).to have_http_status(:ok), response.body
      finding.reload
      expect(finding.state).to eq("false_positive")
      expect(finding.state_changed_by_id).to eq(admin.id)
      expect(finding.state_changed_at).to be_present
      log = Audit::AuditLog.find_by(action: "finding_state_changed", subject_id: finding.id)
      expect(log).to be_present
      expect(log.user_id).to eq(admin.id)
      expect(log.metadata["to"]).to eq("false_positive")
    end

    it "does not require a note for fixed" do
      patch "/api/v1/findings/#{finding.id}", params: { state: "fixed" }, headers: auth(admin, with_client: true), as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(finding.reload.state).to eq("fixed")
    end
  end

  describe "tax scenarios" do
    let!(:scenario) { client.tax_scenarios.create!(effective_from: Date.new(2026, 1, 1), state: "draft", data: { "tax_regime" => "lucro_real" }, created_by: admin) }

    it "audits update and destroy" do
      h = auth(admin)
      patch "/api/v1/clients/#{client.id}/tax_scenarios/#{scenario.id}", params: { data: { tax_regime: "lucro_presumido" } }, headers: h, as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(Audit::AuditLog.where(action: "scenario_updated", subject_id: scenario.id).count).to eq(1)
      delete "/api/v1/clients/#{client.id}/tax_scenarios/#{scenario.id}", headers: h
      expect(response).to have_http_status(:no_content)
      expect(Audit::AuditLog.where(action: "scenario_deleted", subject_id: scenario.id).count).to eq(1)
    end

    it "clamps months on infer" do
      expect(Scenario::Inference).to receive(:new).with(kind_of(Accounts::Client), months: 36).and_return(instance_double(Scenario::Inference, call: {}))
      post "/api/v1/clients/#{client.id}/tax_scenarios/infer", params: { months: 9999 }, headers: auth(admin), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe "admin" do
    it "clamps runs on rule stats" do
      2.times { |i| client.audit_runs.create!(firm:, period_start: Date.new(2026, 6, 1), period_end: Date.new(2026, 6, 30), state: "done", created_at: Time.current - i.hours) }
      get "/api/v1/admin/rules/#{rule.id}/stats", params: { runs: 0 }, headers: auth(platform)
      expect(response).to have_http_status(:ok), response.body
      expect(response.parsed_body["runs"]).to eq(1)
    end

    it "audits reference table create/update" do
      h = auth(platform)
      post "/api/v1/admin/reference_tables", params: { code: "audit_table", name: "Tabela", key_names: %w[uf] }, headers: h, as: :json
      expect(response).to have_http_status(:created), response.body
      id = response.parsed_body["id"]
      expect(Audit::AuditLog.where(action: "reference_table_created", subject_id: id).count).to eq(1)
      patch "/api/v1/admin/reference_tables/#{id}", params: { name: "Tabela 2" }, headers: h, as: :json
      expect(response).to have_http_status(:ok), response.body
      expect(Audit::AuditLog.where(action: "reference_table_updated", subject_id: id).count).to eq(1)
    end
  end
end
