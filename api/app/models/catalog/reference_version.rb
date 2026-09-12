module Catalog
  class ReferenceVersion < ApplicationRecord
    STATES = %w[draft published retired].freeze

    belongs_to :reference_table, class_name: "Catalog::ReferenceTable"
    belongs_to :imported_by, class_name: "Accounts::User", optional: true
    has_many :rows, class_name: "Catalog::ReferenceRow", foreign_key: :reference_version_id, dependent: :delete_all
    scope :published, -> { where(state: "published") }
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }

    validates :state, inclusion: { in: STATES }
    validates :version, :effective_from, presence: true
    validate :effective_until_after_effective_from

    private

    def effective_until_after_effective_from
      return if effective_from.blank? || effective_until.blank?
      errors.add(:effective_until, "deve ser igual ou posterior ao início da vigência") if effective_until < effective_from
    end
  end
end
