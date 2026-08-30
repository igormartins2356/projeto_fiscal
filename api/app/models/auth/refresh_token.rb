module Auth
  class RefreshToken < ApplicationRecord
    belongs_to :user, class_name: "Accounts::User"
    scope :valid, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
    def revoked? = revoked_at.present?
    def expired? = expires_at <= Time.current
  end
end
