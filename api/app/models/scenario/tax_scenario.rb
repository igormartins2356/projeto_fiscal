module Scenario
  class TaxScenario < ApplicationRecord
    belongs_to :client, class_name: "Accounts::Client"
    belongs_to :created_by, class_name: "Accounts::User", optional: true
    validates :effective_from, presence: true

    scope :published, -> { where(state: "published") }
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }

    def self.resolve(client, date)
      published.where(client:).effective_on(date).order(effective_from: :desc).first
    end
  end
end
