class AddAuth < ActiveRecord::Migration[8.1]
  def change
    change_table :users do |t|
      t.string   :otp_secret            # criptografado via Active Record Encryption
      t.boolean  :otp_enabled, null: false, default: false
      t.jsonb    :otp_backup_codes, null: false, default: []   # digests bcrypt
      t.integer  :failed_attempts, null: false, default: 0
      t.datetime :locked_until
      t.boolean  :active, null: false, default: true
      t.datetime :password_changed_at
    end

    create_table :refresh_tokens do |t|
      t.references :user, null: false, foreign_key: true
      t.string   :token_digest, null: false
      t.string   :family, null: false            # rotação: revogar a família inteira em reuso
      t.datetime :expires_at, null: false
      t.datetime :revoked_at
      t.string   :user_agent
      t.string   :ip
      t.timestamps
    end
    add_index :refresh_tokens, :token_digest, unique: true
    add_index :refresh_tokens, :family

    create_table :audit_logs do |t|
      t.references :firm, foreign_key: true
      t.references :user, foreign_key: true
      t.string  :action, null: false            # login, login_failed, mfa_enabled, document_downloaded, ...
      t.string  :subject_type
      t.bigint  :subject_id
      t.jsonb   :metadata, null: false, default: {}
      t.string  :ip
      t.datetime :created_at, null: false
    end
    add_index :audit_logs, [:firm_id, :created_at]
    add_index :audit_logs, [:subject_type, :subject_id]
  end
end
