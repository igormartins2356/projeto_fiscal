require "rails_helper"

RSpec.describe "Clients & tax scenarios", type: :request do
  before { seed_all! }
  let(:token) { post "/api/v1/auth/login", params: { email: "admin@fiscal.local", password: "password123" }; response.parsed_body["access_token"] }
  let(:h) { { "Authorization" => "Bearer #{token}" } }
  let(:client) { Accounts::Client.find_by!(cnpj: "12345678000190") }

  it "creates a client, drafts, publishes and closes previous scenario" do
    post "/api/v1/clients", params: { cnpj: "22.222.222/0001-22", legal_name: "Novo", uf: "MG" }, headers: h
    expect(response).to have_http_status(:created)
    expect(response.parsed_body["cnpj"]).to eq("22222222000122")

    data = { tax_regime: "lucro_presumido", uf: "SP", activity: ["commerce"], pis_cofins: { regime: "cumulative" } }
    post "/api/v1/clients/#{client.id}/tax_scenarios", params: { effective_from: "2026-07-01", data: }, headers: h, as: :json
    expect(response).to have_http_status(:created)
    id = response.parsed_body["id"]
    post "/api/v1/clients/#{client.id}/tax_scenarios/#{id}/publish", headers: h
    expect(response).to have_http_status(:ok)
    old = client.tax_scenarios.find_by!(effective_from: Date.new(2024, 1, 1))
    expect(old.effective_until).to eq(Date.new(2026, 6, 30))
    expect(Scenario::TaxScenario.resolve(client, Date.new(2026, 3, 1)).data["tax_regime"]).to eq("simples_nacional")
    expect(Scenario::TaxScenario.resolve(client, Date.new(2026, 8, 1)).data["tax_regime"]).to eq("lucro_presumido")
    patch "/api/v1/clients/#{client.id}/tax_scenarios/#{id}", params: { data: }, headers: h, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "rejects invalid scenario on publish" do
    post "/api/v1/clients/#{client.id}/tax_scenarios", params: { effective_from: "2026-07-01", data: { tax_regime: "simples_nacional", uf: "SP", activity: ["commerce"], pis_cofins: { regime: "cumulative" } } }, headers: h, as: :json
    post "/api/v1/clients/#{client.id}/tax_scenarios/#{response.parsed_body['id']}/publish", headers: h
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body["errors"]).to include("Simples Nacional exige PIS/COFINS 'simples'")
  end

  it "infers a scenario proposal from documents" do
    Ingestion::DocumentImporter.new(client:).call(nfe_fixture("sale_return_csosn_102"))
    post "/api/v1/clients/#{client.id}/tax_scenarios/infer", params: { months: 12 }, headers: h
    expect(response).to have_http_status(:ok)
    f = response.parsed_body["fields"]
    expect(f["tax_regime"]["value"]).to eq("simples_nacional")
    expect(f["tax_regime"]["confidence"]).to eq(1.0)
    expect(f["pis_cofins"]["value"]["regime"]).to eq("simples")
    expect(f["uses_nfce"]["value"]).to be false
    expect(response.parsed_body["sample"]["documents"]).to eq(1)
  end
end
