module Accounts
  class User < ApplicationRecord
    ROLES = %w[platform_admin firm_admin accountant].freeze
    has_secure_password
    belongs_to :firm
    validates :email, presence: true, uniqueness: true
    validates :role, inclusion: { in: ROLES }

    def platform_admin? = role == "platform_admin"
  end
end
