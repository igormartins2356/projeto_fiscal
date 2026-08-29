module Rules
  class RuleTestCase < ApplicationRecord
    belongs_to :rule, class_name: "Rules::Rule"
    validates :name, :reference_date, presence: true
  end
end
