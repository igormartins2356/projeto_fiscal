require "rails_helper"

# A8/M7: defeito de regra ou de primitiva vira evaluation_error DA REGRA; o run segue e o group_key fica legível.
RSpec.describe Rules::Engine do
  class BoomPrimitive < Rules::Primitives::Base
    register "boom_for_spec"
    scope "document"
    def call = raise(TypeError, "undefined method '<' for nil")
  end

  def rule_for(body, scope: "document")
    Rules::Rule.new(code: "TEST.ENGINE.CASE", version: 1, title: "t", scope:, severity: "error", state: "published",
                    effective_from: Date.new(2020, 1, 1), source_type: "platform", body:)
  end

  def resolved(rule) = Rules::Resolver::ResolvedRule.new(rule:, definition: rule.definition, source: "platform", override_ids: [])

  let(:doc) do
    require Rails.root.join("lib/rule_case_builder")
    RuleCaseBuilder.doc(normal: true).merge("_id" => 1, "role" => "issuer")
  end

  it "records a primitive crash as evaluation_error instead of failing the run" do
    engine = described_class.new([resolved(rule_for({ "primitive" => { "name" => "boom_for_spec" }, "message" => "x" }))], catalog: nil, scenario: {})
    expect { engine.evaluate_document(doc) }.not_to raise_error
    expect(engine.findings).to be_empty
    expect(engine.errors.first).to include(rule_code: "TEST.ENGINE.CASE", error: "TypeError: undefined method '<' for nil", count: 1)
  end

  it "records a non numeric total as evaluation_error (items_sum_matches_totals)" do
    broken = doc.deep_dup
    broken["totals"]["items_sum"] = { "icms" => "180.00" }
    broken["totals"]["icms"] = ""
    body = { "primitive" => { "name" => "items_sum_matches_totals", "params" => { "fields" => %w[icms] } }, "message" => "{{field}}" }
    engine = described_class.new([resolved(rule_for(body))], catalog: nil, scenario: {})
    expect { engine.evaluate_document(broken) }.not_to raise_error
    expect(engine.errors.first[:error]).to include("not numeric")
    expect(engine.findings).to be_empty
  end

  it "renders an absent group_by path as — instead of the Ruby object" do
    body = { "assert" => { "field" => "item.product.cfop", "op" => "eq", "value" => "9999" }, "message" => "CFOP {{item.product.cfop}}",
             "group_by" => ["item.product.cfop", "item.nao.existe"] }
    engine = described_class.new([resolved(rule_for(body, scope: "item"))], catalog: nil, scenario: {})
    engine.evaluate_document(doc)
    expect(engine.findings.first.group_key).to eq("5102|—")
  end
end
