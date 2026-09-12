require "rails_helper"

# M12/A11: validação estática precisa barrar a definição errada antes de ela virar (não) finding.
RSpec.describe Rules::Validator do
  def definition(over = {})
    { "code" => "TEST.VALIDATOR.RULE", "version" => 1, "scope" => "item", "severity" => "error", "dsl_version" => 1,
      "effective_from" => Date.new(2020, 1, 1), "message" => "msg", "assert" => { "field" => "item.icms.rate", "op" => "present" } }.merge(over)
  end
  def errors_for(over) = described_class.new(definition(over)).tap(&:valid?).errors.join(" | ")

  it "requires two elements in between/length_between" do
    expect(errors_for("assert" => { "field" => "item.icms.rate", "op" => "between", "value" => "5000" })).to include("dois elementos")
    expect(errors_for("assert" => { "field" => "item.product.cfop", "op" => "length_between", "value" => 4 })).to include("dois elementos")
    expect(errors_for("assert" => { "field" => "item.icms.rate", "op" => "between", "value" => [0, 30] })).to eq("")
  end

  it "requires numeric tolerances" do
    expect(errors_for("assert" => { "field" => "item.icms.amount", "op" => "approx", "value" => "1", "tolerance" => "abc" })).to include("tolerância deve ser numérica")
    expect(errors_for("assert" => { "field" => "item.icms.amount", "op" => "approx", "value" => "1", "tolerance_pct" => { "param" => "nope" } })).to include("param 'nope' não declarado")
    expect(errors_for("params" => { "tol" => "0.01" }, "assert" => { "field" => "item.icms.amount", "op" => "approx", "value" => "1", "tolerance" => { "param" => "tol" } })).to eq("")
  end

  it "accepts a param declared as false and rejects an unknown dsl_version" do
    expect(errors_for("params" => { "flag" => false }, "assert" => { "field" => "item.icms.rate", "op" => "eq", "value" => { "param" => "flag" } })).to eq("")
    expect(errors_for("dsl_version" => 2)).to include("dsl_version")
  end

  it "checks group_by paths" do
    expect(errors_for("group_by" => ["nada.aqui"])).to include("group_by")
    expect(errors_for("group_by" => ["item.icms.rate"])).to eq("")
  end

  it "walks the evidence condition of a primitive in the item scope" do
    scenario_rule = { "code" => "TEST.VALIDATOR.SCENARIO", "version" => 1, "scope" => "scenario", "severity" => "warning", "dsl_version" => 1,
                      "effective_from" => Date.new(2020, 1, 1), "message" => "{{share_pct}}%",
                      "primitive" => { "name" => "scenario_field_disagreement",
                                       "params" => { "field" => "ipi_taxpayer", "when_field_is" => false, "threshold" => "0.1",
                                                     "evidence" => { "field" => "item.ipi.amount", "op" => "gt", "value" => 0 } } } }
    v = described_class.new(scenario_rule)
    expect(v.valid?).to be(true), v.errors.inspect
    bad = described_class.new(scenario_rule.deep_merge("primitive" => { "params" => { "evidence" => { "field" => "item.ipi.amount", "op" => "zzz" } } }))
    expect(bad.valid?).to be false
    expect(bad.errors.join).to include("primitive.params.evidence: op 'zzz' desconhecido")
  end

  it "rejects the abstract primitive name" do
    expect { Rules::Primitives::Base.find("base") }.to raise_error(Rules::EvaluationError, /unknown primitive/)
    expect(errors_for("assert" => nil, "primitive" => { "name" => "base" })).to include("unknown primitive base")
  end
end
