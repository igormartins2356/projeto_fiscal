require "rails_helper"

RSpec.describe "Users", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Piloto") }
  let!(:platform_admin) { Accounts::User.create!(firm:, name: "Admin", email: "padmin@x.com", password: "password123", role: "platform_admin") }
  let!(:firm_admin) { Accounts::User.create!(firm:, name: "Firma", email: "fadmin@x.com", password: "senha-forte-123", role: "firm_admin") }
  let!(:accountant) { Accounts::User.create!(firm:, name: "Conta", email: "conta@x.com", password: "senha-forte-123", role: "accountant") }

  def auth(email, password)
    post "/api/v1/auth/login", params: { email:, password: }
    { "Authorization" => "Bearer #{response.parsed_body['access_token']}" }
  end

  it "forbids a firm_admin from changing or deactivating a platform_admin of the same firm" do
    h = auth("fadmin@x.com", "senha-forte-123")

    patch "/api/v1/users/#{platform_admin.id}", params: { password: "novasenha1234", email: "hacker@x.com" }, headers: h, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body["error"]).to include("administrador da plataforma")
    expect(platform_admin.reload.authenticate("novasenha1234")).to be false
    expect(platform_admin.authenticate("password123")).to be_truthy
    expect(platform_admin.email).to eq("padmin@x.com")

    patch "/api/v1/users/#{platform_admin.id}", params: { role: "accountant", active: false }, headers: h, as: :json
    expect(response).to have_http_status(:forbidden)
    expect(platform_admin.reload.role).to eq("platform_admin")
    expect(platform_admin.active).to be true

    delete "/api/v1/users/#{platform_admin.id}", headers: h
    expect(response).to have_http_status(:forbidden)
    expect(platform_admin.reload.active).to be true
  end

  it "lets a platform_admin still manage another platform_admin" do
    other = Accounts::User.create!(firm:, name: "Outro", email: "outro@x.com", password: "password123", role: "platform_admin")
    h = auth("padmin@x.com", "password123")
    patch "/api/v1/users/#{other.id}", params: { password: "novasenha1234" }, headers: h, as: :json
    expect(response).to have_http_status(:ok)
    expect(other.reload.authenticate("novasenha1234")).to be_truthy
    delete "/api/v1/users/#{other.id}", headers: h
    expect(response).to have_http_status(:no_content)
    expect(other.reload.active).to be false
  end

  it "lets a firm_admin keep managing an accountant of its own firm" do
    h = auth("fadmin@x.com", "senha-forte-123")
    patch "/api/v1/users/#{accountant.id}", params: { name: "Conta 2", password: "novasenha1234" }, headers: h, as: :json
    expect(response).to have_http_status(:ok)
    expect(accountant.reload.name).to eq("Conta 2")
    expect(accountant.authenticate("novasenha1234")).to be_truthy
    delete "/api/v1/users/#{accountant.id}", headers: h
    expect(response).to have_http_status(:no_content)
    expect(accountant.reload.active).to be false
  end
end
