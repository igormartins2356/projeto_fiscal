module Accounts
  class User < ApplicationRecord
    ROLES = %w[platform_admin firm_admin accountant].freeze
    MAX_FAILED = 5
    LOCK_MINUTES = 15

    has_secure_password
    encrypts :otp_secret
    belongs_to :firm
    has_many :refresh_tokens, class_name: "Auth::RefreshToken", dependent: :delete_all

    validates :email, presence: true, uniqueness: { case_sensitive: false }, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :name, presence: true
    validates :role, inclusion: { in: ROLES }
    validates :password, length: { minimum: 10 }, allow_nil: true
    normalizes :email, with: ->(e) { e.strip.downcase }

    scope :active, -> { where(active: true) }

    def platform_admin? = role == "platform_admin"
    def firm_admin? = role.in?(%w[platform_admin firm_admin])
    def locked? = locked_until.present? && locked_until > Time.current

    def register_failed_attempt!
      attempts = failed_attempts + 1
      update_columns(failed_attempts: attempts, locked_until: (attempts >= MAX_FAILED ? LOCK_MINUTES.minutes.from_now : nil))
    end

    def register_success!
      update_columns(failed_attempts: 0, locked_until: nil, last_sign_in_at: Time.current)
    end

    # ---- TOTP ----
    def otp_provisioning_uri = ROTP::TOTP.new(otp_secret, issuer: "Validador Fiscal").provisioning_uri(email)

    # `after:` impede que o mesmo código de 6 dígitos seja aceito duas vezes dentro da janela de drift
    # (~90 s) — sem isso, um código capturado vale para uma segunda sessão ou para desativar o 2FA.
    def verify_otp(code)
      return false if otp_secret.blank?
      totp = ROTP::TOTP.new(otp_secret)
      used_at = totp.verify(code.to_s.delete(" "), drift_behind: 30, drift_ahead: 30, after: otp_last_used_at&.to_i)
      if used_at
        update_columns(otp_last_used_at: Time.zone.at(used_at))
        return true
      end
      consume_backup_code!(code)
    end

    # Conta inexistente precisa custar o mesmo bcrypt de uma existente; senão o tempo de resposta enumera e-mails.
    def self.dummy_authenticate(password)
      @dummy_digest ||= BCrypt::Password.create(SecureRandom.hex(16),
                                                cost: ActiveModel::SecurePassword.min_cost ? BCrypt::Engine::MIN_COST : BCrypt::Engine.cost)
      BCrypt::Password.new(@dummy_digest) == password.to_s
    end

    def generate_backup_codes!
      codes = Array.new(8) { SecureRandom.alphanumeric(10).downcase }
      update!(otp_backup_codes: codes.map { |c| BCrypt::Password.create(c, cost: 5) })
      codes
    end

    private

    def consume_backup_code!(code)
      idx = otp_backup_codes.index { |d| BCrypt::Password.new(d) == code.to_s.strip.downcase }
      return false unless idx
      update!(otp_backup_codes: otp_backup_codes.reject.with_index { |_, i| i == idx })
      true
    end
  end
end
