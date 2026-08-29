module Catalog
  class ReferenceVersion < ApplicationRecord
    belongs_to :reference_table, class_name: "Catalog::ReferenceTable"
    has_many :rows, class_name: "Catalog::ReferenceRow", foreign_key: :reference_version_id, dependent: :delete_all
    scope :published, -> { where(state: "published") }
    scope :effective_on, ->(date) {
      where("effective_from <= ? AND (effective_until IS NULL OR effective_until >= ?)", date, date)
    }
  end
end
