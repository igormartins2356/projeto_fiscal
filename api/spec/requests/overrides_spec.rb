require "rails_helper"

# Sobreposições (ARQUITETURA §13, DSL_RULES §9): adjust/replace passam pelo Rules::Validator; replace só no escopo da firma.
RSpec.describe "Rule and reference row overrides", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:admin) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let!(:rule) do
    Rules::Rule.create!(code: "TEST.OVERRIDE.RULE", version: 1, title: "t", scope: "item", severity: "error", state: "published", effective_from: Date.new(2020, 1, 1),
                        body: { "assert" => { "field" => "item.icms.cst", "op" => "present" }, "message" => "CST ausente" })
  end
  let!(:table) { Catalog::ReferenceTable.create!(code: "ov_table", name: "Tabela", key_arity: 2, key_names: %w[uf ncm]) }
  let(:h) do
    post "/api/v1/auth/login", params: { email: "ana@x.com", password: "senha-forte-123" }
    { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
  end
  let(:base) { { rule_code: rule.code, source_type: "client", source_id: client.id, effective_from: "2026-01-01", justification: "consulta formal" } }

  describe "POST /rule_overrides" do
    it "rejects an adjust whose merged definition fails Rules::Validator" do
      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(override_action: "adjust", patch: { assert: { field: "item.icms.cst", op: "inexistente" } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("inválida")
      expect(response.parsed_body["errors"].join).to include("op 'inexistente' desconhecido")
      expect(Rules::RuleOverride.count).to eq(0)
    end

    it "accepts a valid adjust" do
      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(override_action: "adjust", patch: { severity: "warning" })
      expect(response).to have_http_status(:created), response.body
      expect(response.parsed_body["patch"]).to eq("severity" => "warning")
    end

    it "requires patch for adjust/replace and effective_from always" do
      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(override_action: "adjust")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Patch")
      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.except(:effective_from).merge(override_action: "disable")
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("Effective from")
    end

    it "only allows replace in firm scope, and validates the full body" do
      body = { assert: { field: "item.icms.cst", op: "eq", value: "00" }, message: "CST deve ser 00" }
      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(override_action: "replace", patch: body)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("substituição integral só é permitida no escopo da firma")

      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(source_type: "firm", source_id: firm.id, override_action: "replace", patch: { assert: { field: "period.documents", op: "present" } })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("message obrigatória")

      post "/api/v1/rule_overrides", headers: h, as: :json, params: base.merge(source_type: "firm", source_id: firm.id, override_action: "replace", patch: body)
      expect(response).to have_http_status(:created), response.body
    end
  end

  describe "PATCH /rule_overrides/:id" do
    let!(:override) { Rules::RuleOverride.create!(base.merge(override_action: "adjust", patch: { "severity" => "warning" }, created_by: admin)) }

    it "re-validates the patch" do
      patch "/api/v1/rule_overrides/#{override.id}", headers: h, as: :json, params: { patch: { assert: { op: "eq" } } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["errors"].join).to include("field obrigatório")
      expect(override.reload.patch).to eq("severity" => "warning")
      patch "/api/v1/rule_overrides/#{override.id}", headers: h, as: :json, params: { patch: { severity: "info" } }
      expect(response).to have_http_status(:ok)
      expect(override.reload.patch).to eq("severity" => "info")
    end
  end

  describe "POST /reference_row_overrides" do
    it "returns 422 (not 500) for unknown table or key with wrong arity" do
      post "/api/v1/reference_row_overrides", headers: h, as: :json, params: { reference_table_id: 0, source_type: "firm", source_id: firm.id, key: ["SP"], data: { rate: "1" }, effective_from: "2026-01-01", justification: "j" }
      expect(response).to have_http_status(:unprocessable_entity)
      post "/api/v1/reference_row_overrides", headers: h, as: :json, params: { reference_table_id: table.id, source_type: "firm", source_id: firm.id, key: ["SP"], data: { rate: "1" }, effective_from: "2026-01-01", justification: "j" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to include("2 parte(s)")
      post "/api/v1/reference_row_overrides", headers: h, as: :json, params: { reference_table_id: table.id, source_type: "firm", source_id: firm.id, data: { rate: "1" }, effective_from: "2026-01-01", justification: "j" }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "audits update" do
      o = Catalog::ReferenceRowOverride.create!(reference_table: table, source_type: "firm", source_id: firm.id, key: %w[SP *], data: { "rate" => "12.00" }, effective_from: Date.new(2026, 1, 1), justification: "j", created_by: admin)
      patch "/api/v1/reference_row_overrides/#{o.id}", headers: h, as: :json, params: { data: { rate: "13.00" } }
      expect(response).to have_http_status(:ok)
      expect(Audit::AuditLog.where(action: "reference_row_override_updated", subject_id: o.id).count).to eq(1)
    end
  end
end
