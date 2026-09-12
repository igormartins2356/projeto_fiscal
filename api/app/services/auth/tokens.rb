module Auth
  # JWT de acesso (curto) + refresh token opaco com rotação por família (reuso revoga a família).
  module Tokens
    ACCESS_TTL = 15.minutes
    MFA_TTL = 5.minutes
    REFRESH_TTL = 30.days
    ALG = "HS256"

    class Invalid < StandardError; end

    def self.secret = ENV.fetch("JWT_SECRET") { Rails.application.secret_key_base }

    # `pwd` = marca da última troca de senha. Sem ela, revogar os refresh tokens não derrubava a sessão:
    # o access token do invasor continuava valendo por até ACCESS_TTL depois do reset feito pelo administrador.
    def self.issue_access(user)
      encode(sub: user.id, firm: user.firm_id, role: user.role, purpose: "access",
             pwd: password_stamp(user), exp: ACCESS_TTL.from_now.to_i)
    end

    def self.password_stamp(user) = user.password_changed_at&.to_i.to_i

    def self.issue_mfa(user)
      encode(sub: user.id, purpose: "mfa", exp: MFA_TTL.from_now.to_i)
    end

    def self.decode(token, purpose:)
      payload, = JWT.decode(token, secret, true, algorithm: ALG)
      raise Invalid, "wrong token purpose" unless payload["purpose"] == purpose
      payload
    rescue JWT::DecodeError => e
      raise Invalid, e.message
    end

    def self.issue_refresh(user, request: nil, family: SecureRandom.uuid)
      raw = SecureRandom.urlsafe_base64(48)
      user.refresh_tokens.create!(token_digest: digest(raw), family:, expires_at: REFRESH_TTL.from_now,
                                  user_agent: request&.user_agent&.first(255), ip: request&.remote_ip)
      raw
    end

    # Rotação: token válido → revoga e emite outro na mesma família. Token já usado → revoga a família (possível roubo).
    def self.rotate_refresh(raw, request: nil)
      record = Auth::RefreshToken.find_by(token_digest: digest(raw)) or raise Invalid, "refresh token unknown"
      # A revogação é a própria reserva do token: duas requisições simultâneas com o mesmo refresh só podem
      # afetar 1 linha, então apenas uma emite o próximo token — a outra cai no caminho de reuso.
      claimed = Auth::RefreshToken.where(id: record.id, revoked_at: nil).where("expires_at > ?", Time.current)
                                  .update_all(revoked_at: Time.current)
      if claimed != 1
        Auth::RefreshToken.where(family: record.family).update_all(revoked_at: Time.current)
        raise Invalid, "refresh token reused or expired"
      end
      user = record.user
      raise Invalid, "usuário inativo" unless user.active
      [user, issue_refresh(user, request:, family: record.family)]
    end

    def self.revoke_refresh(raw)
      Auth::RefreshToken.where(token_digest: digest(raw)).update_all(revoked_at: Time.current)
    end

    def self.digest(raw) = Digest::SHA256.hexdigest(raw)
    def self.encode(payload) = JWT.encode(payload.merge(iat: Time.current.to_i, jti: SecureRandom.hex(8)), secret, ALG)
  end
end
