module Catalog
  class ReferenceRowOverride < ApplicationRecord
    belongs_to :reference_table, class_name: "Catalog::ReferenceTable"
    belongs_to :created_by, class_name: "Accounts::User"
    validates :source_type, inclusion: { in: %w[firm client] }
    validates :justification, presence: true
  end
end
