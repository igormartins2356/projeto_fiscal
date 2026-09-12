require "rails_helper"

# Endurecimento de autenticação (achados A1, A2, A3, A5 e baixos da revisão 2026-09-08).
RSpec.describe "Auth hardening", type: :request do
  let(:firm) { Accounts::Firm.create!(name: "Firma") }
  let!(:user) { Accounts::User.create!(firm:, name: "Ana", email: "ana@x.com", password: "senha-forte-123", role: "firm_admin") }

  def login(email = "ana@x.com", password = "senha-forte-123", env: {})
    post "/api/v1/auth/login", params: { email:, password: }, as: :json, env: env
    response.parsed_body
  end

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  # Ativa o 2FA e devolve o segredo. O código usado aqui fica queimado (ver A2).
  def enable_otp!
    token = login["access_token"]
    post "/api/v1/auth/otp/setup", headers: auth(token)
    secret = response.parsed_body["secret"]
    post "/api/v1/auth/otp/enable", params: { code: ROTP::TOTP.new(secret).now }, headers: auth(token)
    expect(response).to have_http_status(:ok)
    secret
  end

  # Código da janela seguinte: (t+30)/30 == t/30 + 1, sempre um timecode novo aceito por drift_ahead.
  def next_code(secret) = ROTP::TOTP.new(secret).at(Time.now + 30)

  describe "[A1] MFA de conta bloqueada" do
    it "recusa o desafio MFA enquanto a conta está bloqueada" do
      secret = enable_otp!
      body = login
      expect(body["mfa_required"]).to be true
      user.update_columns(failed_attempts: Accounts::User::MAX_FAILED, locked_until: 10.minutes.from_now)

      post "/api/v1/auth/mfa", params: { mfa_token: body["mfa_token"], code: next_code(secret) }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("bloqueada")
      expect(response.parsed_body["access_token"]).to be_nil
    end
  end

  describe "[A2] reuso de código TOTP" do
    it "recusa o mesmo código TOTP uma segunda vez" do
      secret = enable_otp!
      code = next_code(secret)

      post "/api/v1/auth/mfa", params: { mfa_token: login["mfa_token"], code: }, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["access_token"]).to be_present

      post "/api/v1/auth/mfa", params: { mfa_token: login["mfa_token"], code: }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "recusa o código já usado no login para desativar o 2FA" do
      secret = enable_otp!
      code = next_code(secret)
      post "/api/v1/auth/mfa", params: { mfa_token: login["mfa_token"], code: }, as: :json
      access = response.parsed_body["access_token"]

      delete "/api/v1/auth/otp", params: { password: "senha-forte-123", code: }, as: :json, headers: auth(access)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.reload.otp_enabled).to be true
    end
  end

  describe "[A3] throttle com corpo JSON" do
    around do |example|
      Rack::Attack.enabled = true
      Rack::Attack.cache.store.clear
      example.run
    ensure
      Rack::Attack.enabled = false
      Rack::Attack.cache.store.clear
    end

    it "conta tentativas de login por e-mail mesmo com corpo JSON, de IPs diferentes" do
      statuses = 6.times.map do |i|
        login("ana@x.com", "errada", env: { "REMOTE_ADDR" => "203.0.113.#{i + 1}" })
        response.status
      end
      expect(statuses.first(5)).to all(eq(401))
      expect(statuses.last).to eq(429)
    end

    it "conta tentativas de MFA pelo usuário do mfa_token, de IPs diferentes" do
      secret = enable_otp!
      mfa_token = login["mfa_token"]
      statuses = 6.times.map do |i|
        post "/api/v1/auth/mfa", params: { mfa_token:, code: "000000" }, as: :json, env: { "REMOTE_ADDR" => "198.51.100.#{i + 1}" }
        response.status
      end
      expect(statuses.last).to eq(429)
      expect(secret).to be_present
    end
  end

  describe "[A5] reset de senha por administrador" do
    let!(:bia) { Accounts::User.create!(firm:, name: "Bia", email: "bia@x.com", password: "outra-senha-123", role: "accountant") }

    it "revoga as sessões e marca password_changed_at" do
      refresh = login("bia@x.com", "outra-senha-123")["refresh_token"]
      expect(refresh).to be_present
      token = login["access_token"]

      patch "/api/v1/users/#{bia.id}", params: { password: "nova-senha-do-admin" }, as: :json, headers: auth(token)
      expect(response).to have_http_status(:ok)
      expect(bia.reload.password_changed_at).to be_present
      expect(bia.refresh_tokens.valid.count).to eq(0)

      post "/api/v1/auth/refresh", params: { refresh_token: refresh }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "[baixo] enumeração de contas no login" do
    it "usa a mesma mensagem para e-mail inexistente, senha errada e conta bloqueada" do
      login("nao-existe@x.com", "seja-la-o-que-for")
      inexistente = response.parsed_body["error"]
      login("ana@x.com", "errada")
      senha_errada = response.parsed_body["error"]
      user.update_columns(failed_attempts: Accounts::User::MAX_FAILED, locked_until: 10.minutes.from_now)
      login("ana@x.com", "senha-forte-123")
      bloqueada = response.parsed_body["error"]

      expect([inexistente, senha_errada, bloqueada]).to all(eq(senha_errada))
      expect(senha_errada).to eq("credenciais inválidas")
    end

    it "gasta o mesmo bcrypt quando o e-mail não existe" do
      expect(BCrypt::Password).to receive(:new).at_least(:once).and_call_original
      login("nao-existe@x.com", "seja-la-o-que-for")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "[baixo] rotação de refresh token" do
    it "não emite dois tokens quando duas requisições usam o mesmo refresh" do
      raw = login["refresh_token"]
      stale = Auth::RefreshToken.find_by(token_digest: ::Auth::Tokens.digest(raw))
      # simula a corrida: a outra requisição já revogou a linha depois deste find_by
      Auth::RefreshToken.where(id: stale.id).update_all(revoked_at: Time.current)
      allow(Auth::RefreshToken).to receive(:find_by).and_return(stale)

      expect { ::Auth::Tokens.rotate_refresh(raw) }.to raise_error(::Auth::Tokens::Invalid)
      expect(user.refresh_tokens.valid.count).to eq(0)
    end

    it "não emite refresh para usuário inativo" do
      raw = login["refresh_token"]
      user.update_columns(active: false)

      post "/api/v1/auth/refresh", params: { refresh_token: raw }, as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(user.refresh_tokens.valid.count).to eq(0)
    end
  end

  describe "[baixo] filtro de log" do
    it "filtra o parâmetro code (TOTP e backup code)" do
      filtered = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
                                               .filter("code" => "123456", "rule_code" => "ICMS.BASE.CALC")
      expect(filtered["code"]).to eq("[FILTERED]")
      expect(filtered["rule_code"]).to eq("ICMS.BASE.CALC")
    end
  end
end
