# Active Record Encryption (otp_secret etc.). Em produção as chaves vêm do ambiente (KMS/Vault → env).
# Em dev/test usa valores fixos para não depender de credentials.yml.enc.
dev_defaults = Rails.env.production? ? {} : {
  primary_key: "dev-primary-key-0123456789abcdef0123456789abcdef",
  deterministic_key: "dev-deterministic-key-0123456789abcdef01234567",
  key_derivation_salt: "dev-salt-0123456789abcdef0123456789abcdef0123"
}
Rails.application.config.active_record.encryption.primary_key = ENV.fetch("AR_ENCRYPTION_PRIMARY_KEY", dev_defaults[:primary_key])
Rails.application.config.active_record.encryption.deterministic_key = ENV.fetch("AR_ENCRYPTION_DETERMINISTIC_KEY", dev_defaults[:deterministic_key])
Rails.application.config.active_record.encryption.key_derivation_salt = ENV.fetch("AR_ENCRYPTION_KEY_DERIVATION_SALT", dev_defaults[:key_derivation_salt])
