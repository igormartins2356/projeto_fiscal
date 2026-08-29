module Catalog
  class ReferenceTable < ApplicationRecord
    has_many :versions, class_name: "Catalog::ReferenceVersion", foreign_key: :reference_table_id, dependent: :destroy
    has_many :row_overrides, class_name: "Catalog::ReferenceRowOverride", foreign_key: :reference_table_id, dependent: :destroy
    validates :code, :name, presence: true, uniqueness: true

    def version_effective_on(date)
      versions.published.effective_on(date).order(version: :desc).first
    end
  end
end
