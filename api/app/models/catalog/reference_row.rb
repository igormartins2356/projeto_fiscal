module Catalog
  class ReferenceRow < ApplicationRecord
    belongs_to :reference_version, class_name: "Catalog::ReferenceVersion"
  end
end
