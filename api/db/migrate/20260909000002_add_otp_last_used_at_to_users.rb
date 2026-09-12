class AddOtpLastUsedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    # Guarda o timestamp do último código TOTP aceito para impedir reuso dentro da janela de drift.
    add_column :users, :otp_last_used_at, :datetime
  end
end
