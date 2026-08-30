require "rails_helper"

RSpec.describe "Auth", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }
  let!(:client) { Accounts::Client.create!(firm:, cnpj: "12345678000190", legal_name: "C", uf: "SP") }
  let(:other_firm) { Accounts::Firm.create!(name: "Outra") }
  let!(:other_client) { Accounts::Client.create!(firm: other_firm, cnpj: "99999999000199", legal_name: "O", uf: "RJ") }

  def login(email = "ana@x.com", password = "senha-forte-123")
    post "/api/v1/auth/login", params: { email:, password: }
    response.parsed_body
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  it "logs in, refreshes with rotation and rejects reuse" do
    body = login
    expect(response).to have_http_status(:ok)
    expect(body["access_token"]).to be_present
    get "/api/v1/auth/me", headers: auth(body["access_token"])
    expect(response.parsed_body["email"]).to eq("ana@x.com")

    post "/api/v1/auth/refresh", params: { refresh_token: body["refresh_token"] }
    expect(response).to have_http_status(:ok)
    second = response.parsed_body
    post "/api/v1/auth/refresh", params: { refresh_token: body["refresh_token"] }  # reuso
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/refresh", params: { refresh_token: second["refresh_token"] } # família revogada
    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects bad credentials and locks after repeated failures" do
    5.times { login("ana@x.com", "errada") }
    expect(response).to have_http_status(:unauthorized)
    expect(user.reload.locked?).to be true
    login
    expect(response.parsed_body["error"]).to include("bloqueada")
  end

  it "requires auth and scopes clients by firm" do
    get "/api/v1/clients"
    expect(response).to have_http_status(:unauthorized)
    token = login["access_token"]
    get "/api/v1/clients", headers: auth(token)
    expect(response.parsed_body.map { |c| c["id"] }).to eq([client.id])
    get "/api/v1/audit_runs", headers: auth(token).merge("X-Client-Id" => other_client.id.to_s)
    expect(response).to have_http_status(:unprocessable_entity)
    get "/api/v1/audit_runs", headers: auth(token).merge("X-Client-Id" => client.id.to_s)
    expect(response).to have_http_status(:ok)
  end

  it "enables TOTP and requires it on login" do
    token = login["access_token"]
    post "/api/v1/auth/otp/setup", headers: auth(token)
    secret = response.parsed_body["secret"]
    expect(response.parsed_body["qr_svg"]).to include("<svg")
    post "/api/v1/auth/otp/enable", params: { code: ROTP::TOTP.new(secret).now }, headers: auth(token)
    expect(response).to have_http_status(:ok)
    backup = response.parsed_body["backup_codes"]
    expect(backup.size).to eq(8)

    body = login
    expect(body["mfa_required"]).to be true
    post "/api/v1/auth/mfa", params: { mfa_token: body["mfa_token"], code: "000000" }
    expect(response).to have_http_status(:unauthorized)
    post "/api/v1/auth/mfa", params: { mfa_token: body["mfa_token"], code: ROTP::TOTP.new(secret).now }
    expect(response.parsed_body["access_token"]).to be_present
    post "/api/v1/auth/mfa", params: { mfa_token: login["mfa_token"], code: backup.first }
    expect(response).to have_http_status(:ok)
    post "/api/v1/auth/mfa", params: { mfa_token: login["mfa_token"], code: backup.first }
    expect(response).to have_http_status(:unauthorized) # backup code é de uso único
  end

  it "manages users within the firm only" do
    token = login["access_token"]
    post "/api/v1/users", params: { name: "Bia", email: "bia@x.com", password: "outra-senha-123", role: "accountant" }, headers: auth(token)
    expect(response).to have_http_status(:created)
    expect(Accounts::User.find_by(email: "bia@x.com").firm_id).to eq(firm.id)
    bia_token = login("bia@x.com", "outra-senha-123")["access_token"]
    get "/api/v1/users", headers: auth(bia_token)
    expect(response).to have_http_status(:forbidden)
  end
end
