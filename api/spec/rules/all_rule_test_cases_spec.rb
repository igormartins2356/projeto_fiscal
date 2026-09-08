require "rails_helper"

# Regressão da base de regras: todos os casos de teste de todas as regras (seed) precisam passar.
RSpec.describe "rule test cases" do
  before { seed_all! }

  it "passes every seeded test case and every rule has at least one firing and one non-firing case" do
    failures = []
    Rules::Rule.where.not(state: "retired").includes(:test_cases).find_each do |rule|
      expect(rule.test_cases.any? { |t| t.expect["findings"].present? }).to be(true), "#{rule.code} v#{rule.version} sem caso que dispara"
      expect(rule.test_cases.any? { |t| t.expect["findings"].blank? }).to be(true), "#{rule.code} v#{rule.version} sem caso que não dispara"
      Rules::TestRunner.new(rule).run_all.reject(&:passed).each { |r| failures << "#{rule.code} v#{rule.version} — #{r.test_case.name}: #{r.details.join('; ')} #{r.errors.map { |e| e[:error] }.join('; ')}" }
    end
    expect(failures).to eq([])
  end

  it "validates statically every rule" do
    invalid = Rules::Rule.where.not(state: "retired").find_each.filter_map { |r| v = Rules::Validator.new(r.definition); v.valid? ? nil : "#{r.code}: #{v.errors.join('; ')}" }
    expect(invalid).to eq([])
  end
end
